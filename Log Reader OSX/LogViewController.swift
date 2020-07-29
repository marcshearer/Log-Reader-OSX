//
//  LogViewController.swift
//  Log Reader OSX
//
//  Created by Marc Shearer on 07/04/2019.
//  Copyright © 2019 Marc Shearer. All rights reserved.
//

import Cocoa

class LogViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, CommsStateDelegate, CommsDataDelegate, CommsConnectionDelegate {
    
    private var multipeerHost: CommsServerHandlerDelegate?
    private var entries: [LogEntry] = []
    private var unique: [String : LogEntry] = [:]
    private var devices: [String : Device] = [:]
    private var deviceFromRow: [Device] = []
    private var filteredEntries: [LogEntry] = []
    private var searchText = ""
    private var matchDeviceName = ""
    private var excludeLogger = true
    private var scrollToLatest = true
    private var layout: [Layout]?
    private var total: [Int?]!
    private var totals = false
    private let colors = [NSColor.black, NSColor.red, NSColor.blue, NSColor.green, NSColor.yellow, NSColor.orange, NSColor.gray]
    private var fileOpen = false
    private var lastDirectory: URL?
    
    private var menuItem: [String:NSMenuItem?] = [:]
    private var recentMenuItem: [NSMenuItem?] = []
    
    private var recentFileUrls: [String?] = []
    
    @IBOutlet private weak var devicesTableView: NSTableView!
    @IBOutlet private weak var messagesTableView: NSTableView!
    @IBOutlet private weak var searchField: NSSearchFieldCell!
    @IBOutlet private weak var excludeLoggerButton: NSButton!
    @IBOutlet private weak var scrollToLatestButton: NSButton!
    
    @IBAction func openMenuSelected(_ sender: Any) {
        self.openLogfile()
    }
    
    @IBAction func openRecentMenuSelected(_ menuItem :NSMenuItem) {
        if let fileUrl = self.recentFileUrls[menuItem.tag - 1] {
            self.openSpecificLogFile(fileUrl: fileUrl)
        }
    }

    @IBAction func closeMenuSelected(_ sender: Any) {
        self.closeLogFile()
    }
    
    @IBAction func clearMenuSelected(_ sender: Any) {
        self.clearLogFile()
    }
    
    @IBAction func saveAsMenuSelected(_ sender: Any) {
        self.saveAsLogFile()
    }

    @IBAction func searchChanged(_ sender: NSSearchFieldCell) {
        self.searchText = searchField.stringValue
        self.resetSelection()
    }
    
    @IBAction func excludeLoggerPressed(_ sender: NSButton) {
        if self.excludeLogger != (self.excludeLoggerButton.state == .on) {
            self.excludeLogger = (self.excludeLoggerButton.state == .on)
            self.resetSelection()
        }
    }
    
    @IBAction func scrollToLatestPressed(_ sender: NSButton) {
        if self.scrollToLatest != (self.scrollToLatestButton.state == .on) {
            self.scrollToLatest = (self.scrollToLatestButton.state == .on)
            if self.scrollToLatest {
                self.messagesTableView.scrollRowToVisible(self.filteredEntries.count-1)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.resetAll()
        
        // Start listener service
        multipeerHost = MultipeerServerService(purpose: .playing, serviceID: "whist-logger")
        self.multipeerHost?.stateDelegate = self as CommsStateDelegate?
        self.multipeerHost?.dataDelegate = self as CommsDataDelegate?
        self.multipeerHost?.connectionDelegate = self as CommsConnectionDelegate?
        self.multipeerHost?.start()
        
        self.setupLayout()
        self.setupGrid(displayTableView: messagesTableView, layout: self.layout!)
                
        // Switch off focus on devices and set focus to search
        devicesTableView.focusRingType = .none
        devicesTableView.refusesFirstResponder = true
        messagesTableView.refusesFirstResponder = true
        searchField.refusesFirstResponder = false
        searchField.placeholderString = "Filter text"
        
        //Setup menus
        self.setupMenus()
        self.loadRecentList()
        self.enableMenus()
        
        // Get last load/save directory
        self.loadLastDirectory()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    // MARK: - TableView Overrides ===================================================================== -

    internal func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView.tag {
        case 1:
            // Device list
            return self.devices.count
        case 2:
            // Message list
            return self.filteredEntries.count
        default:
            return 0
        }
    }
    
    internal func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch tableView.tag {
        case 1:
            // Device list
            self.matchDeviceName = self.deviceFromRow[row].deviceName
            self.resetSelection()
            return true
        case 2:
            // Message list
            return false
        default:
            return false
        }
    }
    
    internal func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false
    }
        
    internal func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        var cell: NSTextFieldCell?
        
        switch tableView.tag {
        case 1:
            // Device list
            let deviceName = deviceFromRow[row].deviceName
            cell = NSTextFieldCell(textCell: (deviceName == "" ? "All devices" : deviceName))
            cell?.textColor = deviceFromRow[row].color
        case 2:
            // Message list
            if let identifier = tableColumn?.identifier.rawValue {
                if let column = Int(identifier) {
                    switch self.layout![column].key {
                    case "device":
                        cell = NSTextFieldCell(textCell: self.filteredEntries[row].deviceName ?? "")
                    case "timestamp":
                        cell = NSTextFieldCell(textCell: self.filteredEntries[row].timestamp ?? "")
                    case "source":
                        cell = NSTextFieldCell(textCell: self.filteredEntries[row].source ?? "")
                    case "message":
                        cell = NSTextFieldCell(textCell: self.filteredEntries[row].message?.replacingOccurrences(of: "\n", with: " ") ?? "")
                    default:
                        break
                    }
                    cell?.textColor = devices[self.filteredEntries[row].deviceName!]!.color
                }
            }
        default:
            break
        }
        return cell
    }
    
    internal func tableView(_ tableView: NSTableView, shouldShowCellExpansionFor tableColumn: NSTableColumn?, row: Int) -> Bool {
        return true
    }
    
    internal func tableView(_ tableView: NSTableView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, row: Int,  mouseLocation: NSPoint) -> String {
        var result = ""
        var line = ""
        var level = 0
        var lines = 0
        var inArray = 0
        var lastClosing = false
        var spaceSkipping = false
        var matchSession = false
        var matchSessionStart = false
        let indent = 1
        let pad = "\t"
        var skipping = 0
                
        if let message = self.filteredEntries[row].message?.replacingOccurrences(of: "\n", with: " ") {
            
            for char in message {
                
                if skipping > 0 {
                    skipping -= 1
                } else {
                    
                    switch char {
                    case "(", ",":
                        line += String(char)
                        if (inArray == 0 || !lastClosing) || char != "," {
                            if char == "(" {
                                level += 1
                                result += line + String(repeating: pad, count: indent - 1)
                            } else {
                                result += line + "\n" + String(repeating: pad, count: indent * level)
                            }
                            line = ""
                            lines += 1
                            lastClosing = false
                        }
                        if char == "," && matchSession {
                            matchSessionStart = true
                        }
                        spaceSkipping = true
                    case ")":
                        level -= 1
                        line += String(char)
                        lastClosing = true
                        lines += 1
                        spaceSkipping = false
                    case "[":
                        if line.replacingOccurrences(of: " ", with: "") == "matchSessionUUIDs=" {
                            // Special case - skip most of UUID
                            matchSession = true
                            matchSessionStart = true
                        }
                        line += String(char)
                        inArray -= 1
                        lastClosing = true
                        spaceSkipping = false
                    case "]":
                        line += String(char)
                        inArray += 1
                        lastClosing = true
                        spaceSkipping = false
                        matchSession = false
                    case " ":
                        if !spaceSkipping {
                            line += String(char)
                        }
                    default:
                        if matchSession && matchSessionStart {
                            // Looks like we're into a second session UUID - skip most of it
                            matchSessionStart = false
                            skipping = 31
                        } else {
                            line += String(char)
                        }
                        lastClosing = true
                        spaceSkipping = false
                    }
                }
            }
            result += line
        }
        
        return result
    }
    
    
    // MARK: - Menu Option Setup ======================================================================== -

    private func setupMenus() {
        let mainMenu = NSApplication.shared.mainMenu!
        let subMenu = mainMenu.item(withTag: 1)?.submenu

        self.menuItem["open"] = subMenu?.item(withTag: 1)
        self.menuItem["openRecent"] = subMenu?.item(withTag: 2)
        self.menuItem["close"] = subMenu?.item(withTag: 3)
        self.menuItem["clear"] = subMenu?.item(withTag: 4)
        self.menuItem["saveAs"] = subMenu?.item(withTag: 5)
        
        for index in 0...3 {
            self.recentMenuItem.append(self.menuItem["openRecent"]??.submenu?.item(withTag: index + 1))
        }
        self.menuItem["openRecent"]??.isEnabled = true
        
        subMenu?.item(withTitle: "Cut")?.isEnabled = false
    }
    
    private func enableMenus() {
        self.menuItem["close"]??.isEnabled = self.fileOpen
        self.menuItem["clear"]??.isEnabled = !self.fileOpen
        self.menuItem["saveAs"]??.isEnabled = !self.entries.isEmpty
        self.menuItem["openRecent"]??.isEnabled = !self.recentFileUrls.isEmpty
    }
    
    private func loadRecentList() {
        // Load from user defaults
        self.recentFileUrls = []
        for index in 0...3 {
            self.recentFileUrls.append(UserDefaults.standard.string(forKey: "recent\(index+1)"))
        }
            
        // Remove any blanks
        for index in (0...3).reversed() {
            if self.recentFileUrls[index] == "" {
                self.recentFileUrls.remove(at: index)
            }
        }
        self.updateRecentMenu()
    }
    
    private func insertRecentList(fileUrl: String) {
        // First remove if already there
        if let index = self.recentFileUrls.firstIndex(where: {$0 == fileUrl}) {
            self.recentFileUrls.remove(at: index)
        }
                
        // Insert at top
        self.recentFileUrls.insert(fileUrl, at: 0)
        
        // Remove last entry if too many
        if self.recentFileUrls.count > 4 {
            self.recentFileUrls.remove(at: 4)
        }
        
        // Save to user defaults
        for index in 0...3 {
            UserDefaults.standard.set(self.recentFileUrls[index], forKey: "recent\(index+1)")
        }
        
        // Update menu
        self.updateRecentMenu()
    }

    private func updateRecentMenu() {
        for index in 0...3 {
            if self.recentFileUrls[index] ?? "" == "" {
                self.recentMenuItem[index]?.isHidden = true
            } else {
                self.recentMenuItem[index]?.title = URL(string: self.recentFileUrls[index]!)!.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "Error"
                self.recentMenuItem[index]?.isHidden = false
            }
        }
    }
        
    // MARK: - Last directory load/save =================================================================== -
    
    func loadLastDirectory() {
        if let defaultsLastDirectory = UserDefaults.standard.string(forKey: "lastDirectory") {
            if let lastDirectory = URL(string: defaultsLastDirectory) {
                self.lastDirectory = lastDirectory
            }
        }
    }
    
    func saveLastDirectory(_ lastFilename: URL) {
        self.lastDirectory = lastFilename.deletingLastPathComponent()
        UserDefaults.standard.set(self.lastDirectory!.absoluteString, forKey: "lastDirectory")
    }
    
    // MARK: - Menu Option Methods ======================================================================== -

    private func openLogfile() {
        
        self.chooseOpenFileUrl() { (fileUrl) in
            self.openSpecificLogFile(fileUrl: fileUrl.absoluteString)
        }
    }
    
    private func openSpecificLogFile(fileUrl: String) {
        let entryState = multipeerHost?.handlerState
        
        do {
            if let fileUrl = URL(string: fileUrl) {
                let json = try String(contentsOf: fileUrl, encoding: .utf8)
                if let logList = self.decode(json: json) {
                    var sequence = 0
                    
                    // Stop receiving logs
                    self.multipeerHost?.stop()
                    
                    // Clear current logs
                    self.resetAll()
                    
                    // Insert entries from file
                    for logEntry in logList {
                        if let deviceName = logEntry["deviceName"] {
                            if self.devices[deviceName] == nil {
                                _ = self.addDevice(deviceName)
                            }
                            self.processData(dictionary: logEntry, sequence:sequence, deviceName: deviceName, update: false)
                            sequence += 1
                        }
                    }
                    
                    // Show in table
                    self.resetSelection()
                    
                    // Flag opening
                    self.fileOpen = true
                    
                    // Update menus
                    self.enableMenus()
                    self.insertRecentList(fileUrl: fileUrl.absoluteString)
                    
                } else {
                    self.error(entryState: entryState)
                }
            }
        } catch {
            print(error.localizedDescription)
            self.error(entryState: entryState)
        }
    }
    
    private func error(entryState: CommsHandlerState?) {
        Utility.alertMessage("Error opening file")
        if entryState != .notStarted {
            self.multipeerHost?.start()
        }
    }
    
    private func closeLogFile() {
        self.resetAll()
        self.resetSelection()
        self.multipeerHost?.stop()
        self.multipeerHost?.start()
        
        // Flag closing
        self.fileOpen = false
        
        // Enable menus
        self.enableMenus()
    }
    
    private func clearLogFile() {
        self.resetAll(includeDevices: false)
        self.resetSelection()
                
        // Enable menus
        self.enableMenus()
    }
        
    private func saveAsLogFile() {
        self.chooseSaveFileUrl() { (fileUrl) in
            if let data = self.serialise() {
                do {
                    try data.write(to: fileUrl, atomically: true, encoding: String.Encoding.utf8)
                    self.insertRecentList(fileUrl: fileUrl.absoluteString)
                } catch {
                    Utility.alertMessage("Error writing new file")
                }
            } else {
                Utility.alertMessage("Error writing new file")
            }
        }
    }
    
    // MARK: - Utility Methods ======================================================================== -

    private func resetAll(includeDevices: Bool = true) {
        
        self.messagesTableView.beginUpdates()

        self.filteredEntries = []

        self.messagesTableView.endUpdates()


        self.devicesTableView.beginUpdates()

        self.entries = []
        self.unique = [:]
        self.searchText = ""

        if includeDevices {
            self.devices = [:]
            self.deviceFromRow = []
            self.matchDeviceName = ""
        }

        self.devicesTableView.endUpdates()
        
        if includeDevices {
            // Pre-fill "all" device
            _ = self.addDevice("", color: NSColor.darkGray)
            self.devicesTableView.reloadData()
        }

    }
    
    private func addDevice(_ deviceName: String, color: NSColor? = nil) -> Device {
        let color = color ?? self.colors[min(self.deviceFromRow.count-1, self.colors.count-1)]
        let device = Device(deviceName: deviceName, row: self.deviceFromRow.count, color: color)
        self.deviceFromRow.append(device)
        self.devices[deviceName] = device
        self.devicesTableView.reloadData()
        
        return device
    }
    
    private func resetSelection() {
        self.messagesTableView.beginUpdates()
        if self.filteredEntries.count > 0 {
            self.messagesTableView.removeRows(at: IndexSet(integersIn: 0...self.filteredEntries.count-1))
            self.filteredEntries = []
        }
        for entry in self.entries {
            if match(entry: entry) {
                self.filteredEntries.append(entry)
            }
        }
        self.messagesTableView.reloadData()
        self.messagesTableView.endUpdates()
    }
    
    private func setupGrid(displayTableView: NSTableView, layout: [Layout]) {
        // Remove any existing columns
        for tableColumn in displayTableView.tableColumns {
            displayTableView.removeTableColumn(tableColumn)
        }
        
        self.total = []
        self.totals = false

        for index in 0..<layout.count {
            let column = layout[index]
            let tableColumn = NSTableColumn()
            let headerCell = NSTableHeaderCell()
            headerCell.title = column.title
            headerCell.alignment = column.alignment
            tableColumn.headerCell = headerCell
            if column.width < 0 && tableColumn.headerCell.cellSize.width > abs(column.width) {
                tableColumn.width = tableColumn.headerCell.cellSize.width + 10
            } else {
                tableColumn.width = abs(column.width)
            }
            tableColumn.identifier = NSUserInterfaceItemIdentifier("\(index)")
            displayTableView.addTableColumn(tableColumn)

            self.total.append(column.total ? 0 : nil)
            self.totals = true
        }
        // Add a blank column
        let tableColumn=NSTableColumn()
        tableColumn.headerCell.title = ""
        tableColumn.width = 1.0
        displayTableView.addTableColumn(tableColumn)
    }
    
    private func setupLayout() {
        
        self.layout =
            [ Layout(key: "device",     title: "Device",    width: 140,     alignment: .left,   type: .string,  total: false),
              Layout(key: "timestamp",  title: "Time",      width: 80,      alignment: .center, type: .string,  total: false),
              Layout(key: "source",     title: "Source",    width: 80,      alignment: .center, type: .string,  total: false),
              Layout(key: "message",    title: "Message",   width: -3000,   alignment: .left,   type: .string,  total: false) ]
    }
    
    private func match(entry: LogEntry) -> Bool {
        var matched = true
        
        if self.excludeLogger && entry.source == "logger" {
            matched = false
            
        } else {
            
            if self.searchText != "" {
                matched = matched &&
                    ((entry.message?.lowercased() ?? "").contains(self.searchText.lowercased()) ||
                     (entry.source?.lowercased() ?? "").contains(self.searchText.lowercased()))
            }
            if self.matchDeviceName != "" {
                matched = matched && (entry.deviceName == self.matchDeviceName)
            }
        }
        
        return matched
    }
    
    // MARK: - Comms Delegates ======================================================================== -
    
    internal func stateChange(for peer: CommsPeer, reason: String?) {
        
        Utility.mainThread {
            
            // Send last UUID and sequence to trigger history refresh
            if peer.state == .connected {
                // Add to device table if necessary
                var device = self.devices[peer.deviceName]
                var lastUUID = ""
                var lastSequence = 0
                if device == nil {
                    device = self.addDevice(peer.deviceName)
                    self.devicesTableView.reloadData()
                } else {
                    lastUUID = device!.lastUUID ?? ""
                    lastSequence = device!.lastSequence ?? 0
                }
                // Send last log UUID and sequence to trigger refresh
                let data : [String : Any] = [ "uuid"      : lastUUID,
                                              "sequence"  : lastSequence ]
                self.multipeerHost?.send("lastSequence", data, to: peer)
                print( lastSequence)
            }
        }
    }
    
    internal func didReceiveData(descriptor: String, data: [String : Any?]?, from peer: CommsPeer) {
        
        Utility.mainThread {
            
            let deviceName = peer.deviceName
            
            if self.entries.count >= 10000 {
                
                if self.match(entry: self.entries[0]) {
                    // Currently displayed - remove it
                    self.messagesTableView.beginUpdates()
                    self.filteredEntries.remove(at:  0)
                    self.messagesTableView.removeRows(at: IndexSet(integer: 0))
                    self.messagesTableView.endUpdates()
                }
                
                // Remove first entry from total list
                self.entries.remove(at: 0)
            }
            
            for (sequence, dictionary) in data as! [String : [String : Any]] {
                self.processData(dictionary: dictionary, sequence: Int(sequence) ?? 0, deviceName: deviceName)
            }
            
            self.enableMenus()
        }
    }
    
    private func processData(dictionary: [String : Any], sequence: Int, deviceName: String, update: Bool = true) {
        if let logUUID = dictionary["uuid"] as! String?,
            let timestamp = dictionary["timestamp"] as! String?,
            let source = dictionary["source"] as! String?,
            let message = dictionary["message"]  as! String? {
            
            let uniqueKey = "\(deviceName)-\(logUUID)-\(sequence)"
            
            if self.unique[uniqueKey] == nil {
                
                // Not in list - Add it
                let entry = LogEntry(uuid: logUUID, deviceName: deviceName, timestamp: timestamp, source: source, message: message)
                var index = self.entries.firstIndex(where: {$0.timestamp! > timestamp})
                if index == nil {
                    index = self.entries.count
                }
                self.entries.insert(entry, at: index!)
                self.unique[uniqueKey] = entry
                
                // Check if device name already in device list
                if let device = self.devices[deviceName] {
                    // Save last UUID and sequence
                    device.lastUUID = logUUID
                    device.lastSequence = Int(sequence)
                }
                
                // Check if in filtered list
                if update && self.match(entry: entry) {
                    // Gets past filter - add to the currently displayed list
                    self.messagesTableView.beginUpdates()
                    var index = self.filteredEntries.firstIndex(where: {$0.timestamp! > timestamp})
                    if index == nil {
                        index = self.filteredEntries.count
                    }
                    self.filteredEntries.insert(entry, at: index!)
                    self.messagesTableView.insertRows(at: IndexSet(integer: index!))
                    self.messagesTableView.endUpdates()
                    if self.scrollToLatest {
                        self.messagesTableView.scrollRowToVisible(self.filteredEntries.count-1)
                    }
                }
            }
        }
    }

    func connectionReceived(from peer: CommsPeer, info: [String : Any?]?) -> Bool {
        return true
    }
    
    private func serialise() -> String? {
        var propertyList: [[String : Any]] = []
        var json: String?
        
        for entry in self.entries {
            if entry.source != "logger" {
                propertyList.append([ "uuid"       : entry.uuid        ,
                                      "deviceName" : entry.deviceName! ,
                                      "timestamp"  : entry.timestamp!  ,
                                      "source"     : entry.source!     ,
                                      "message"    : entry.message!    ])
            }
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: propertyList, options: .prettyPrinted)
            json = String(data: data, encoding: .utf8)
        } catch {
            // Just return nil
        }
        
        return json
    }
    
    private func decode(json: String) -> [[String : String]]? {
        var dictionary: [[String : String]]?
        
        if let data = json.data(using: .utf8) {
            do {
                dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [[String : String]]
            } catch {
            }
        }
        
        return dictionary
    }
    
    private func chooseSaveFileUrl(completion: @escaping (URL)->()) {
        
        let savePanel = NSSavePanel()
        if let lastDirectory = self.lastDirectory {
            savePanel.directoryURL = lastDirectory
        } else {
            savePanel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        savePanel.canCreateDirectories = true
        savePanel.title = "Save log file"
        savePanel.message = "Enter the name of the file to save"
        savePanel.prompt = "Save"
        savePanel.level = .floating
        savePanel.allowedFileTypes = [ "logx" ]
        savePanel.allowsOtherFileTypes = false
        savePanel.begin { result in
            if result == .OK {
                completion(savePanel.url!)
                self.saveLastDirectory(savePanel.url!)
            }
        }
    }
    
    private func chooseOpenFileUrl(completion: @escaping (URL)->()) {
        
        let openPanel = NSOpenPanel()
        if let lastDirectory = self.lastDirectory {
            openPanel.directoryURL = lastDirectory
        } else {
            openPanel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = [ "logx" ]
        openPanel.allowsOtherFileTypes = false
        openPanel.prompt = "Open"
        openPanel.level = .floating
        openPanel.begin { result in
            if result == .OK {
                completion(openPanel.urls[0])
                self.saveLastDirectory(openPanel.urls[0])
            }
        }
    }
}

fileprivate class LogEntry {
    public var uuid: String
    public var deviceName: String?
    public var timestamp: String?
    public var message: String?
    public var source: String?
    
    init(uuid: String, deviceName: String?, timestamp: String?, source: String?, message:String?) {
        self.uuid = uuid
        self.deviceName = deviceName
        self.timestamp = timestamp
        self.source = source
        self.message = message
    }
}

fileprivate class Device {
    public var deviceName: String
    public var color: NSColor?
    public var row: Int
    public var lastUUID: String?
    public var lastSequence: Int?

    init(deviceName: String, row: Int, color: NSColor) {
        self.deviceName = deviceName
        self.row = row
        self.color = color
    }
}

fileprivate enum VarType {
    case string
    case date
    case dateTime
    case int
    case double
    case bool
}
    
fileprivate struct Layout {
    var key: String
    var title: String
    var width: CGFloat
    var alignment: NSTextAlignment
    var type: VarType
    var total: Bool
}
