//
//  ViewController.swift
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

    
    @IBOutlet private weak var devicesTableView: NSTableView!
    @IBOutlet private weak var messagesTableView: NSTableView!
    @IBOutlet private weak var searchField: NSSearchFieldCell!
    @IBOutlet private weak var excludeLoggerButton: NSButton!
    @IBOutlet private weak var scrollToLatestButton: NSButton!

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

        // Start listener service
        multipeerHost = MultipeerServerService(purpose: .playing, serviceID: "whist-logger")
        self.multipeerHost?.stateDelegate = self as CommsStateDelegate?
        self.multipeerHost?.dataDelegate = self as CommsDataDelegate?
        self.multipeerHost?.connectionDelegate = self as CommsConnectionDelegate?
        multipeerHost?.start()
        
        self.setupLayout()
        self.setupGrid(displayTableView: messagesTableView, layout: self.layout!)
        
        // Pre-fill "all" device
        _ = self.addDevice("", color: NSColor.darkGray)
        
        // Switch off focus on devices and set focus to search
        devicesTableView.focusRingType = .none
        devicesTableView.refusesFirstResponder = true
        messagesTableView.refusesFirstResponder = true
        searchField.refusesFirstResponder = false
        searchField.placeholderString = "Filter text"
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
                        cell = NSTextFieldCell(textCell: self.filteredEntries[row].message ?? "")
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
    
    // MARK: - Utility Methods ======================================================================== -

    private func addDevice(_ deviceName: String, color: NSColor) -> Device {
        let device = Device(deviceName: deviceName, row: self.deviceFromRow.count, color: color)
        self.deviceFromRow.append(device)
        self.devices[deviceName] = device
        
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
              Layout(key: "message",    title: "Message",   width: -1000,   alignment: .left,   type: .string,  total: false) ]
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
                    device = self.addDevice(peer.deviceName, color: self.colors[min(self.deviceFromRow.count-1, self.colors.count-1)])
                    self.devicesTableView.reloadData()
                } else {
                    lastUUID = device!.lastUUID ?? ""
                    lastSequence = device!.lastSequence ?? 0
                }
                // Send last log UUID and sequence to trigger refresh
                let data : [String : Any] = [ "uuid"      : lastUUID,
                                              "sequence"  : lastSequence ]
                self.multipeerHost?.send("lastSequence", data, to: peer)
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
                if let logUUID = dictionary["uuid"] as! String?,
                   let timestamp = dictionary["timestamp"] as! String?,
                   let source = dictionary["source"] as! String?,
                   let message = dictionary["message"] as! String? {
                    
                    let uniqueKey = "\(deviceName)-\(logUUID)-\(sequence)"
                    
                    if self.unique[uniqueKey] == nil {
                        
                        // Not in list - Add it
                        let entry = LogEntry(deviceName: deviceName, timestamp: timestamp, source: source, message: message)
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
                        if self.match(entry: entry) {
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
        }
    }
    
    func connectionReceived(from peer: CommsPeer, info: [String : Any?]?) -> Bool {
        return true
    }
    
}

fileprivate class LogEntry {
    public var deviceName: String?
    public var timestamp: String?
    public var message: String?
    public var source: String?
    public var expanded = false
    
    init(deviceName: String?, timestamp: String?, source: String?, message:String?) {
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
