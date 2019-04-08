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
    private var devices: [String : Device] = [:]
    private var deviceFromRow: [Device] = []
    private var filteredEntries: [LogEntry] = []
    private var searchText = ""
    private var layout: [Layout]?
    private var total: [Int?]!
    private var totals = false

    
    @IBOutlet private weak var devicesTableView: NSTableView!
    @IBOutlet private weak var messagesTableView: NSTableView!

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
        var cell: NSCell!
        
        switch tableView.tag {
        case 1:
            // Device list
            cell=NSCell(textCell: deviceFromRow[row].deviceName)
        case 2:
            // Message list
            if let identifier = tableColumn?.identifier.rawValue {
                if let column = Int(identifier) {
                    switch column {
                    case 0:
                        cell=NSCell(textCell: self.entries[row].deviceName ?? "")
                    case 1:
                        cell=NSCell(textCell: self.entries[row].timestamp ?? "")
                    case 2:
                        cell=NSCell(textCell: self.entries[row].message ?? "")
                    default:
                        break
                    }
                }
            }
        default:
            break
        }
        return cell
    }

    // MARK: - Utility Methods ======================================================================== -

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
            [ Layout(key: "device",               title: "Device",        width: 140,      alignment: .left,   type: .string,      total: false),
              Layout(key: "timestamp",            title: "Time",          width: 80,      alignment: .center, type: .string,      total: false),
              Layout(key: "message",              title: "Message",       width: -1000,    alignment: .left,   type: .string,      total: false) ]
    }
    
    private func match(entry: LogEntry) -> Bool {
        if self.searchText == "" {
            return true
        } else {
            var combined: String
            if let deviceName = entry.deviceName {
                combined = deviceName + " " + (entry.message ?? "")
            } else {
                combined = entry.message ?? ""
            }
            return (combined.lowercased().contains(searchText.lowercased()))
        }
    }
    
    // MARK: - Comms Delegates ======================================================================== -
    
    internal func stateChange(for peer: CommsPeer, reason: String?) {
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
            
            let timestamp = data?["timestamp"] as! String?
            let message = data?["message"] as! String?
            
            // Add to total list
            let entry = LogEntry(deviceName: deviceName, timestamp: timestamp, message: message)
            self.entries.append(entry)
            
            if self.match(entry: entry) {
                // Gets past filter - add to the currently displayed list
                self.messagesTableView.beginUpdates()
                self.filteredEntries.append(entry)
                self.messagesTableView.insertRows(at: IndexSet(integer: self.filteredEntries.count-1))
                self.messagesTableView.endUpdates()
                self.messagesTableView.scrollRowToVisible(self.filteredEntries.count-1)
            }
            
            // Check if already in device list
            if self.devices[deviceName] == nil {
                let device = Device(deviceName: deviceName, row: self.deviceFromRow.count)
                self.deviceFromRow.append(device)
                self.devices[deviceName] = device
                self.devicesTableView.reloadData()
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
    public var expanded = false
    
    init(deviceName: String?, timestamp: String?, message:String?) {
        self.deviceName = deviceName
        self.timestamp = timestamp
        self.message = message
    }
}

fileprivate class Device {
    public var deviceName: String
    public var color: NSColor?
    public var row: Int

    init(deviceName: String, row: Int) {
        self.deviceName = deviceName
        self.row = row
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
