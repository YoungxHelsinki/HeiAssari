//
//  ViewController.swift
//  HeiAssari
//
//  Created by Park Seyoung on 17/10/16.
//  Copyright © 2016 Park Seyoung. All rights reserved.
//

import UIKit
import AudioToolbox
import WebKit
import Kanna
import AVFoundation
import UserNotifications

struct Constants {
    
    static let isDebugging = false
    
    static let aPlusURL = "https://plus.cs.hut.fi/"
    
    static let greenGoblinURLprefix = "https://greengoblin.cs.hut.fi/neuvontajono/sessions/"
    static let greenGoblinURLsuffix = "/manage"
    
    static let defaultLabelText = "☝🏼Instruction \nGo to your course. \n🖱Click: \n1.Menu(🍔) at top right \n2.Neuvontajono \n3.Jonon hallinta \n4.YOUR GROUP"
    static let isOnManagePageLabelText = "Now we will notify you when a student joins the queue. You may press home button or lock your iPhone. \n\nYour iPhone might get little warm because it's playing silent mp3 so it doesn't get suspended by the OS."
}

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    var webView: WKWebView!
    var label: UILabel!
    var audioPlayer: AVAudioPlayer!
    var students = [Student]()
    var queueChecker = Timer()
    var oldHTMLTable: String = ""
    
    private var isOnManagePage: Bool = false {
        didSet {
            if oldValue == false && isOnManagePage {
                label.text = Constants.isOnManagePageLabelText
                queueChecker = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(parseManagePage), userInfo: nil, repeats: true)
            } else if !isOnManagePage {
                queueChecker.invalidate()
                label.text = Constants.defaultLabelText
            }
        }
    }
    
    func parseManagePage() {
        // WKWebView cannot get AJAX updates when the app enters background
        // Reload is an easy workaround
        webView.reload()
        
        let url = webView.url!.absoluteString
        print(">>> parseManagePage() @ \(url)")
        
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") {
            (html: Any?, error: Error?) -> Void in
            self.parseHTML(html: html as! String)
        }
        
        scheduleNotification(isDebugging: Constants.isDebugging)    // Debug purpose
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadNavBarButtons()
        loadWebView()
        loadLabel()
        loadAVAudioSession()
        loadAudioPlayer()
        webView.goHome()
    }
    
    func loadNavBarButtons() {
        navigationItem.title = "HeiAssari"
        
        
        let backackButton:UIButton = UIButton(type: UIButtonType.custom) as UIButton
        backackButton.addTarget(webView, action: #selector(webView.goBack), for: .touchUpInside)
        let image = UIImage(named: "back")
        backackButton.setImage(image, for: .normal)
//        backackButton.setTitle("< Back", for: .normal)
        
        backackButton.setTitleColor(UIColor.blue, for: .normal)
        backackButton.sizeToFit()
        let backButtonItem = UIBarButtonItem(customView: backackButton)
        
        navigationItem.leftBarButtonItem = backButtonItem
        
        
        let homeButton:UIButton = UIButton(type: UIButtonType.custom) as UIButton
        homeButton.addTarget(webView, action: #selector(webView.goHome), for: .touchUpInside)
        homeButton.setTitle("A+", for: .normal)
        homeButton.setTitleColor(UIColor.blue, for: .normal)
        homeButton.sizeToFit()
        let homeButtonItem = UIBarButtonItem(customView: homeButton)

        navigationItem.rightBarButtonItem = homeButtonItem
    }
    
    func loadAVAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: [.defaultToSpeaker])
            NSLog("Succeeded to set audio session category.")
        } catch {
            NSLog("Failed to set audio session category.  Error: \(error)")
        }
        
    }
    
    func loadAudioPlayer() {
        guard let songURL = Bundle.main.url(forResource: "silent", withExtension: "mp3") else {
            print("Cannot load the song url")
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: songURL)
        } catch {
            print("Cannot load the song: \(error)")
        }
        audioPlayer.numberOfLoops = -1    // Infinite loop
        audioPlayer.play()
    }

    func loadWebView() {
        
        let frame = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height * 0.7))
        webView = WKWebView(frame: frame)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        view.addSubview(webView)
    }
    
    func loadLabel() {
        let webViewHeight = webView.bounds.height
        let frame = CGRect(
            origin: CGPoint(x: 0, y: webViewHeight),
            size: CGSize(
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.height - webViewHeight))
        label = UILabel(frame: frame)
        label.numberOfLines = 0
        label.text = Constants.defaultLabelText
        label.textColor = UIColor.white
        view.addSubview(label)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print(">>> finish loading")
        
        let isURLPrefixManagePagePrefix = webView.url!.absoluteString.hasPrefix(Constants.greenGoblinURLprefix)
        let isURLSuffixManagePagePrefix = webView.url!.absoluteString.hasSuffix(Constants.greenGoblinURLsuffix)
        isOnManagePage = isURLPrefixManagePagePrefix && isURLSuffixManagePagePrefix
    }
    
    
    /**
     This method is a delegate method of WKUIDelegate. It's for opening Neuvontajono link
     Without this, you can't open a link which is supposed to be opened in a new tab/window.
     */
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        print(">>> createWebViewWith configuration")

        guard navigationAction.targetFrame == nil else { return nil }
        
        webView.load(navigationAction.request)
        
        return nil
    }
    
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(WKNavigationActionPolicy.allow)
    }
    
    func isTableContentNew(oldHTMLTable: inout String, newHTML: String) -> Bool {
        guard let doc = Kanna.HTML(html: newHTML, encoding: String.Encoding.utf8) else {
            return false
        }
        
        /**
         I'm not sure what doc.css("table#queue tbody tr").underestimatedCount is.
         So I count in a for-loop instead.
         */
        
        let tableAsXPath = doc.css("table#queue tbody tr")
        var newHTMLTable = ""
        
        tableAsXPath.forEach { p in
            if let text = p.text {
                newHTMLTable += text
            }
        }
        
        //        print(oldHTMLTable)
        //        print(newHTMLTable)
        
        let result = oldHTMLTable != newHTMLTable
        oldHTMLTable = newHTMLTable
        return result
        
    }
    
    func parseHTML(html: String) -> Void {
        print(">>> @parseHTML()")
        guard isTableContentNew(oldHTMLTable: &oldHTMLTable, newHTML: html) else { print("    Nothing new"); return }
        
        if let doc = Kanna.HTML(html: html, encoding: String.Encoding.utf8) {
            
            /**
             I'm not sure what doc.css("table#queue tbody tr").underestimatedCount is.
             So I count in a for-loop instead.
             */
            
            let table = doc.css("table#queue tbody tr")
            var newTableHTML = ""
            
            /// For some reason reduce didn't work
            table.forEach { p in
                if let text = p.text {
                    newTableHTML += text
                }
            }
            
            //            table.reduce("") { p in
            //                let base = p.0
            //                if let text = p.1.text {
            //                    return base + text
            //                }
            //                return base
            //            }
            
            var queueLength = 0
            
            for row in doc.css("table#queue tbody tr") {
                
                queueLength += 1
                
                let rowTrimmed = row.text!.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
                let rowSeparated = rowTrimmed.components(separatedBy: "\n").map{
                    $0.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
                }
                
                if rowSeparated.count < 4 { break }
                
                self.parseRow(row: rowSeparated, queueLength: queueLength)
            }
            UIApplication.shared.applicationIconBadgeNumber = queueLength
        }
    }
    
    func parseRow(row: [String], queueLength: Int){
        let name = row[1]
        let time = row[2]
        if self.isNotStudentInQueue(name: name, time: time) {
            let seat = row[3]
            self.pushStudentToQueue(name: name, time: time, seat: seat, queueLength: queueLength)
        } else {
            print(">>> Already in queue")
        }
    }
    
    func isNotStudentInQueue(name: String, time: String) -> Bool {
        let studentsWithSameName = students.filter { $0.name == name }
        guard let _ = studentsWithSameName.first else {
            return true  // Because we don't want to add it to the queue
        }
        return studentsWithSameName.filter { $0.time == time }.isEmpty
    }
    
    func pushStudentToQueue(name: String, time:String, seat: String, queueLength badgeNumber: Int) {
        print(">>> pushStudentToQueue()")
        let student = Student(name: name, time: time, seat: seat)
        students.append(student)
        vibratePhone()
        scheduleNotification(student: student, badgeNumber: badgeNumber)
    }
    

    func scheduleNotification(student: Student, badgeNumber badge: Int) {
        let content = UNMutableNotificationContent()
        content.title = student.name
        content.subtitle = student.time
        content.body = student.seat
        content.badge = badge as NSNumber
        
        let requestIdentifier = student.name + student.time
        // trigger: nil => Immediate notification
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) {
            error in
        }
    }
    
    
    /**
     Only for debugging
     */
    var badge = 1
    func scheduleNotification(isDebugging: Bool) {
        guard isDebugging else { return }
        let time = String(NSDate().timeIntervalSince1970)
        let student = Student(name: "ss", time: time, seat: String(badge))
        scheduleNotification(student: student, badgeNumber: badge)
        badge += 1
    }

}

struct Student {
    let name: String
    let time: String
    let seat: String
    var timeAsInt: Int {
        // 14:30 => 14*60 + 30
        let hourAndMinute: [String] = time.components(separatedBy: ":")
        guard let hourAsString = hourAndMinute.first,
            let minuteAsString = hourAndMinute.last,
            let hour = Int(hourAsString),
            let minute = Int(minuteAsString)  else {
            print("Wrong time input: \(hourAndMinute)")
            return -1
        }
        return hour * 60 + minute
    }
}

extension ViewController {
    fileprivate func vibratePhone() {
        print(">>> vibratePhone()")
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

extension WKWebView {
    func load(urlAsString: String) {
        guard let url = URL(string: urlAsString) else { print("Invalid URL: \(urlAsString)"); return }
        let urlRequest = URLRequest(url: url)
        load(urlRequest)
    }
    
    func goHome() {
        load(urlAsString: Constants.aPlusURL)
    }
}
