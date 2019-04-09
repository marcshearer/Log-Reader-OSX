//
//  Multipeer Class.swift
//  Contract Whist Scorecard
//
//  Created by Marc Shearer on 31/05/2017.
//  Copyright © 2017 Marc Shearer. All rights reserved.
//
//  Class to implement gaming/sharing between devices using Multipeer connectivity

import Foundation
import MultipeerConnectivity

class MultipeerService: NSObject, CommsHandlerDelegate, MCSessionDelegate {
    
    // Main class variables
    public let connectionMode: CommsConnectionMode = .broadcast
    public let connectionFramework: CommsConnectionFramework = .multipeer
    public let connectionProximity: CommsConnectionProximity = .nearby
    public let connectionType: CommsConnectionType
    public let connectionPurpose: CommsConnectionPurpose
    public var connectionUUID: String?
    private var _connectionEmail: String?
    internal var _connectionDevice: String?
    public var connectionEmail: String? {
        get {
            return _connectionEmail
        }
    }
    public var connectionDevice: String? {
        get {
            return _connectionDevice
        }
    }
    public var connections: Int {
        get {
            return self.sessionList.count
        }
    }
    
    // Delegates
    public var stateDelegate: CommsStateDelegate!
    public var dataDelegate: CommsDataDelegate!
    
    // Other state variables
    internal var serviceID: String
    internal var sessionList: [String : MCSession] = [:]
    internal var broadcastPeerList: [String: BroadcastPeer] = [:]
    internal var myPeerID: MCPeerID
    
    init(purpose: CommsConnectionPurpose, type: CommsConnectionType, serviceID: String?, deviceName: String) {
        self.connectionPurpose = purpose
        self.connectionType = type
        self.serviceID = serviceID!
        self.myPeerID = MCPeerID(displayName: Host.current().localizedName!)
    }
    
    internal func startService(email: String!, recoveryMode: Bool, matchDeviceName: String! = nil) {
        self._connectionEmail = email
    }
    
    internal func stopService() {
        self._connectionEmail = nil
    }
    
    internal func endSessions(matchDeviceName: String! = nil) {
        // End all connections - or possibly just for one remote device if specified
        for (deviceName, session) in self.sessionList {
            if matchDeviceName == nil || matchDeviceName == deviceName {
                endSession(session: session)
                self.sessionList[deviceName] = nil
            }
        }
    }
    
    internal func endSession(session: MCSession) {
        self.debugMessage("End Session")
        session.disconnect()
        session.delegate = nil
    }
    
    internal func disconnect(from commsPeer: CommsPeer, reason: String = "", reconnect: Bool) {
        let deviceName = commsPeer.deviceName
        if let broadcastPeer = broadcastPeerList[deviceName] {
            broadcastPeer.shouldReconnect = reconnect
            broadcastPeer.reconnect = reconnect
            broadcastPeer.state = .notConnected
            self.stateDelegate?.stateChange(for: commsPeer, reason: reason)
        }
        self.send("disconnect", ["reason" : reason], to: commsPeer)
    }
    
    internal func send(_ descriptor: String, _ dictionary: Dictionary<String, Any?>! = nil, to commsPeer: CommsPeer? = nil, matchEmail: String? = nil) {
        var toDeviceName: String! = nil
        if let commsPeer = commsPeer {
            toDeviceName = commsPeer.deviceName
        }
        self.debugMessage("Sending \(descriptor)", device: toDeviceName)
        
        let data = prepareData(descriptor, dictionary)
        if data != nil {
            
            for (deviceName, session) in self.sessionList {
                
                if toDeviceName == nil || deviceName == toDeviceName {
                    do {
                        if let broadcastPeer = broadcastPeerList[deviceName] {
                            if matchEmail == nil || (broadcastPeer.playerEmail != nil && broadcastPeer.playerEmail! == matchEmail) {
                                try session.send(data!, toPeers: [broadcastPeer.mcPeer], with: .reliable)
                            }
                        }
                    } catch {
                        // Ignore errors
                    }
                }
            }
        }
    }
    
    private func prepareData(_ descriptor: String, _ dictionary: Dictionary<String, Any?>! = nil) -> Data? {
        let propertyList: [String : [String : Any?]?] = [descriptor : dictionary]
        var data: Data
        
        do {
            data = try JSONSerialization.data(withJSONObject: propertyList, options: .prettyPrinted)
        } catch {
            // Ignore errors
            return nil
        }
        
        return data
    }
    
    internal func reset() {
        // Over-ridden in client
    }
    
    internal func connectionInfo() {
    }
    
    internal func debugMessage(_ message: String, device: String? = nil, force: Bool = false) {
        var outputMessage = message
        if let device = device {
            outputMessage = outputMessage + " Device: \(device)"
        }
        Utility.debugMessage("multipeer", message, force: force)
    }
    
    // MARK: - Session delegate handlers ========================================================== -
    
    internal func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        debugMessage("Session change state to \((state == MCSessionState.notConnected ? "Not connected" : (state == .connected ? "Connected" : "Connecting")))", device: peerID.displayName)
        
        let deviceName = peerID.displayName
        if let broadcastPeer = broadcastPeerList[deviceName] {
            let currentState = broadcastPeer.state
            broadcastPeer.state = commsConnectionState(state)
            if broadcastPeer.state == .notConnected{
                if currentState == .reconnecting {
                    // Have done a reconnect and it has now failed - reset connection
                    self.reset()
                }
                if broadcastPeer.reconnect {
                    // Reconnect
                    broadcastPeer.state = .reconnecting
                    self.debugMessage("Reconnecting", device: deviceName)
                } else {
                    // Clear peer
                    broadcastPeerList[deviceName] = nil
                }
            } else if state == .connected {
                // Connected - activate reconnection if selected on connection
                broadcastPeer.reconnect = broadcastPeer.shouldReconnect
            }
            // Call delegate
            stateDelegate?.stateChange(for: broadcastPeer.commsPeer)
        } else {
            // Not in peer list - can't carry on
            self.disconnect(from: BroadcastPeer(parent: self, mcPeer: peerID, deviceName: deviceName).commsPeer, reason: "Unexpected connection")
        }
        
        if state == .notConnected {
            // Clear session
            sessionList[deviceName] = nil
        } else {
            // Save session
            sessionList[deviceName] = session
        }
    }
    
    internal func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let deviceName = peerID.displayName
            if let broadcastPeer = broadcastPeerList[deviceName] {
                let propertyList: [String : Any?] = try JSONSerialization.jsonObject(with: data, options: []) as! [String : Any]
                if propertyList.count != 0 {
                    for (descriptor, values) in propertyList {
                        debugMessage("Received \(descriptor)")
                        if descriptor == "disconnect" {
                            var reason = ""
                            if values != nil {
                                let stringValues = values as! [String : String]
                                if stringValues["reason"] != nil {
                                    reason = stringValues["reason"]!
                                }
                            }
                            self.endSessions(matchDeviceName: deviceName)
                            broadcastPeer.state = .notConnected
                            broadcastPeer.reconnect = false
                            if stateDelegate != nil {
                                stateDelegate?.stateChange(for: broadcastPeer.commsPeer, reason: reason)
                            }
                        } else if values is NSNull {
                            dataDelegate?.didReceiveData(descriptor: descriptor, data: nil, from: broadcastPeer.commsPeer)
                        } else {
                            dataDelegate?.didReceiveData(descriptor: descriptor, data: values as! [String : Any]?, from: broadcastPeer.commsPeer)
                        }
                    }
                }
            }
        } catch {
        }
    }
    
    internal func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not implemented
    }
    
    internal func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not implemented
    }
    
    internal func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not implemented
    }
    
    // MARK: - Utility Methods ========================================================================= -
    
    private func commsConnectionState(_ state: MCSessionState) -> CommsConnectionState {
        switch state {
        case .notConnected:
            return .notConnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        }
    }
}


// RabbitMQ Server Service Class ========================================================================= -

class MultipeerServerService : MultipeerService, CommsServerHandlerDelegate, MCNearbyServiceAdvertiserDelegate {
    
    private struct ServerConnection {
        var advertiser: MCNearbyServiceAdvertiser!
    }
    
    internal var handlerState: CommsHandlerState = .notStarted
    private var server: ServerConnection!
    
    // Delegates
    public weak var connectionDelegate: CommsConnectionDelegate!
    public weak var handlerStateDelegate: CommsHandlerStateDelegate!
    
    required init(purpose: CommsConnectionPurpose, serviceID: String?, deviceName: String) {
        super.init(purpose: purpose, type: .server, serviceID: serviceID, deviceName: deviceName)
    }
    
    // MARK: - Comms Handler Server handlers ========================================================================= -
    
    internal func start(email: String!, queueUUID: String!, name: String!, invite: [String]!, recoveryMode: Bool) {
        self.debugMessage("Start Server \(self.connectionPurpose)")
        
        super.startService(email: email, recoveryMode: recoveryMode)
        
        let advertiser = MCNearbyServiceAdvertiser(peer: self.myPeerID, discoveryInfo: nil, serviceType: self.serviceID)
        self.server = ServerConnection(advertiser: advertiser)
        self.server.advertiser.delegate = self
        self.server.advertiser.startAdvertisingPeer()
        changeState(to: .broadcasting)
        
    }
    
    internal func stop() {
        self.debugMessage("Stop Server \(self.connectionPurpose)")
        
        super.stopService()
        
        self.broadcastPeerList = [:]
        if self.server != nil {
            if self.server.advertiser != nil {
                self.server.advertiser.stopAdvertisingPeer()
                self.server.advertiser.delegate = nil
                self.server.advertiser = nil
            }
            self.server = nil
        }
        self.endSessions()
        changeState(to: .notStarted)
    }
    
    // MARK: - Comms Handler State handler =================================================================== -
    
    internal func changeState(to state: CommsHandlerState) {
        self.handlerState = state
        self.handlerStateDelegate?.handlerStateChange(to: state)
    }
    
    // MARK: - Advertiser delegate handlers ======================================================== - -
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
        var playerName: String?
        var playerEmail: String?
        let deviceName = peerID.displayName
        var propertyList: [String : String]! = nil
        if context != nil {
            do {
                propertyList = try JSONSerialization.jsonObject(with: context!, options: []) as? [String : String]
            } catch {
            }
            playerName = propertyList["player"]
            playerEmail = propertyList["email"]
        }
        
        // End any pre-existing sessions since should only have 1 connection at a time
        endSessions(matchDeviceName: deviceName)
        
        // Create / replace peer data
        let broadcastPeer = BroadcastPeer(parent: self, mcPeer: peerID, deviceName: deviceName, playerEmail: playerEmail, playerName: playerName)
        self.broadcastPeerList[deviceName] = broadcastPeer
        
        // Create session
        let session = MCSession(peer: self.myPeerID, securityIdentity: nil, encryptionPreference: .none)
        self.sessionList[deviceName] = session
        session.delegate = self
        
        if connectionDelegate != nil {
            if connectionDelegate.connectionReceived(from: broadcastPeer.commsPeer, info: propertyList) {
                invitationHandler(true, session)
            }
        } else {
            invitationHandler(true, session)
        }
    }
    
    
}


// Multipeer Client Service Class ========================================================================= -

class MultipeerClientService : MultipeerService, CommsClientHandlerDelegate, MCNearbyServiceBrowserDelegate {
    
    private struct ClientConnection {
        var browser: MCNearbyServiceBrowser!
    }
    
    private var client: ClientConnection!
    private var matchDeviceName: String!
    
    // Delegates
    public weak var browserDelegate: CommsBrowserDelegate!
    
    required init(purpose: CommsConnectionPurpose, serviceID: String?, deviceName: String) {
        super.init(purpose: purpose, type: .client, serviceID: serviceID, deviceName: deviceName)
    }
    
    // Comms Handler Client Service handlers ========================================================================= -
    
    internal func start(email: String!, name: String!, recoveryMode: Bool, matchDeviceName: String!) {
        self.debugMessage("Start Client \(self.connectionPurpose)")
        
        super.startService(email: email, recoveryMode: recoveryMode, matchDeviceName: matchDeviceName)
        
        let browser = MCNearbyServiceBrowser(peer: self.myPeerID, serviceType: serviceID)
        self.client = ClientConnection(browser: browser)
        self.client.browser.delegate = self
        self.client.browser.startBrowsingForPeers()
    }
    
    internal func stop() {
        self.debugMessage("Stop Client \(self.connectionPurpose)")
        
        super.stopService()
        
        self.endSessions()
        self.endConnections()
        
        self.broadcastPeerList = [:]
        if self.client != nil {
            if self.client.browser != nil {
                self.client.browser.stopBrowsingForPeers()
                self.client.browser.delegate = nil
                self.client.browser = nil
            }
            self.client  = nil
        }
    }
    
    internal func connect(to commsPeer: CommsPeer, playerEmail: String?, playerName: String?, context: [String : String]?, reconnect: Bool = true) -> Bool{
        self.debugMessage("Connect to \(String(describing: commsPeer.deviceName))")
        if let broadcastPeer = self.broadcastPeerList[commsPeer.deviceName] {
            broadcastPeer.shouldReconnect = reconnect
            broadcastPeer.playerEmail = playerEmail
            broadcastPeer.playerName = playerName
            var data: Data! = nil
            if let playerName = playerName {
                do {
                    var context = context
                    if context == nil {
                        context = [:]
                    }
                    context!["player"] = playerName
                    if let playerEmail = playerEmail {
                        context!["email"] = playerEmail
                    }
                    data = try JSONSerialization.data(withJSONObject: context!, options: .prettyPrinted)
                } catch {
                    Utility.alertMessage("Error connecting to device", title: "Error")
                    return false
                }
            }
            let session = MCSession(peer: self.myPeerID, securityIdentity: nil, encryptionPreference: .none)
            session.delegate = self
            self.sessionList[broadcastPeer.deviceName] = session
            self.client.browser.invitePeer(broadcastPeer.mcPeer, to: session, withContext: data, timeout: 5)
            self._connectionDevice = broadcastPeer.deviceName
            return true
        } else {
            Utility.alertMessage("Device not recognized", title: "Error")
            return false
        }
    }
    
    internal override func reset() {
        self.debugMessage("Restart browsing")
        self.client.browser.stopBrowsingForPeers()
        self.client.browser.startBrowsingForPeers()
    }
    
    // MARK: - Browser delegate handlers ===================================================== -
    
    internal func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        browserDelegate?.error("Unable to connect. Check that wifi is enabled")
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        let deviceName = peerID.displayName
        if deviceName != self.myPeerID.displayName {
            
            debugMessage("Found peer \(peerID.displayName)", device: peerID.displayName)
            
            // End any pre-existing sessions
            self.endSessions(matchDeviceName: deviceName)
            
            var broadcastPeer = self.broadcastPeerList[deviceName]
            if broadcastPeer == nil {
                broadcastPeer = BroadcastPeer(parent: self, mcPeer: peerID, deviceName: deviceName)
                broadcastPeerList[deviceName] = broadcastPeer
            } else {
                broadcastPeer?.mcPeer = peerID
            }
            
            if broadcastPeer!.reconnect {
                // Auto-reconnect set - try to connect
                if !self.connect(to: broadcastPeer!.commsPeer, playerEmail: broadcastPeer?.playerEmail, playerName: broadcastPeer?.playerName, reconnect: true) {
                    // Not good - shouldn't happen - try stopping browsing and restarting - will retry when find peer again
                    self.client.browser.stopBrowsingForPeers()
                    self.client.browser.startBrowsingForPeers()
                    broadcastPeer!.state = .reconnecting
                    stateDelegate?.stateChange(for: broadcastPeer!.commsPeer)
                }
            } else {
                // Notify delegate
                browserDelegate?.peerFound(peer: broadcastPeer!.commsPeer)
            }
        }
    }
    
    internal func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let deviceName = peerID.displayName
        if deviceName != self.myPeerID.displayName {
            
            debugMessage("Lost peer \(peerID.displayName)", device: peerID.displayName)
            
            if let broadcastPeer = broadcastPeerList[deviceName] {
                if broadcastPeer.reconnect {
                    if broadcastPeer.state != .reconnecting {
                        // Notify delegate since not already aware we are trying to reconnect
                        broadcastPeer.state = .reconnecting
                        stateDelegate?.stateChange(for: broadcastPeer.commsPeer)
                    }
                } else {
                    // Notify delegate peer lost
                    browserDelegate?.peerLost(peer: broadcastPeer.commsPeer)
                }
            }
        }
    }
    
    // MARK: - Session delegate handlers ========================================================== -
    
    internal override func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        
        super.session(session, peer: peerID, didChange: state)
        
        // Start / stop browsing
        if self.client != nil && self.client.browser != nil {
            if state == .notConnected {
                // Lost connection - need to start browsing for another one
                self.debugMessage("Start browsing")
                self.client.browser.startBrowsingForPeers()
            } else if state == .connected {
                // Connected - stop browsing
                self.debugMessage("Stop browsing")
                self.client.browser.stopBrowsingForPeers()
            }
        }
    }
    
    // MARK: - Utility Methods ======================================================================== -
    
    private func endConnections(matchDeviceName: String! = nil) {
        Utility.debugMessage("multipeer", "End connections (\(broadcastPeerList.count))")
        for (deviceName, broadcastPeer) in broadcastPeerList {
            if matchDeviceName == nil || matchDeviceName == deviceName {
                if broadcastPeer.state == .connecting {
                    // Change back to not connected and notify
                    broadcastPeer.state = .notConnected
                    self.stateDelegate?.stateChange(for: broadcastPeer.commsPeer)
                }
            }
        }
    }
}



// Broadcast Peer Class ========================================================================= -

public class BroadcastPeer {
    
    public var mcPeer: MCPeerID
    public var playerEmail: String?
    public var playerName: String?
    public var state: CommsConnectionState
    public var reason: String?
    public var reconnect: Bool = false
    public var shouldReconnect: Bool = false
    private var parent: MultipeerService
    public var deviceName: String {
        get {
            return mcPeer.displayName
        }
    }
    
    init(parent: MultipeerService, mcPeer: MCPeerID, deviceName: String, playerEmail: String? = "", playerName: String? = "") {
        self.parent = parent
        self.mcPeer = mcPeer
        self.playerEmail = playerEmail
        self.playerName = playerName
        self.state = .notConnected
    }
    
    public var commsPeer: CommsPeer {
        get {
            return CommsPeer(parent: self.parent as CommsHandlerDelegate, deviceName: self.deviceName, playerEmail: self.playerEmail, playerName: self.playerName, state: self.state, reason: reason, autoReconnect: reconnect)
        }
    }
    
}

