//
//  SessionsViewController.swift
//  EventBlank
//
//  Created by Marin Todorov on 6/20/15.
//  Copyright (c) 2015 Underplot ltd. All rights reserved.
//

import UIKit
import SQLite
import XLPagerTabStrip

let kFavoritesToggledNotification = "kFavoritesToggledNotification"
let kFavoritesChangedNotification = "kFavoritesChangedNotification"

class SessionsViewController: UIViewController, XLPagerTabStripChildItem, UITableViewDataSource, UITableViewDelegate {

    var day: ScheduleDay! //set from container VC
    var items = [ScheduleDaySection]()

    var favorites = [Int]()
    var speakerFavorites = [Int]()
    
    var delegate: SessionViewControllerDelegate! //set from previous VC
    
    var database: Database {
        return DatabaseProvider.databases[eventDataFileName]!
        }
    
    var event: Row {
        return (UIApplication.sharedApplication().delegate as! AppDelegate).event
    }
    
    let dateFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
        formatter.timeStyle = .ShortStyle
        formatter.dateFormat = .None
        return formatter
        }()
    
    var lastSelectedSession: Row?
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        backgroundQueue(loadItems, completion: {
            self.tableView.reloadData()
        })

        observeNotification(kFavoritesToggledNotification, selector: "didToggleFavorites")
        observeNotification(kFavoritesChangedNotification, selector: "didChangeFavorites")
        observeNotification(kScrollToCurrentSessionNotification, selector: "scrollToCurrentSession:")
        //observeNotification(kDidReplaceEventFileNotification, selector: "didChangeEventFile")
    }
    
    deinit {
        observeNotification(kFavoritesToggledNotification, selector: nil)
        observeNotification(kFavoritesChangedNotification, selector: nil)
        observeNotification(kScrollToCurrentSessionNotification, selector: nil)
        //observeNotification(kDidReplaceEventFileNotification, selector: nil)
    }
    
    func loadItems() {
        
        //load favorites
        favorites = Favorite.allSessionFavoritesIDs()
        speakerFavorites = Favorite.allSpeakerFavoriteIDs()
        
        //load sessions
        var sessions = database[SessionConfig.tableName]
            .join(database[SpeakerConfig.tableName], on: {Session.fk_speaker == Speaker.idColumn}())
            .join(database[TrackConfig.tableName], on: {Session.fk_track == Track.idColumn}())
            .join(database[LocationConfig.tableName], on: {Session.fk_location == Location.idColumn}())
            .filter(Session.beginTime > Int(day.startTimeStamp) && Session.beginTime < Int(day.endTimeStamp))
            .order(Session.beginTime.asc)
            .map {$0}
        
        //filter sessions
        if delegate.isFavoritesFilterOn() {
            sessions = sessions.filter({ session in
                return find(self.favorites, session[Session.idColumn]) != nil ||
                    (find(self.speakerFavorites, session[Speaker.idColumn]) != nil)
            })
        }
        
        //build schedule sections
        items = Schedule().groupSessionsByStartTime(sessions)
        
        mainQueue({
            //show no sessions message
            if self.items.count == 0 {
                self.tableView.addSubview(MessageView(text: "No sessions match your current filter"))
            } else {
                MessageView.removeViewFrom(self.tableView)
            }
        })
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let detailsVC = segue.destinationViewController as? SessionDetailsViewController {
            detailsVC.session = lastSelectedSession
        }
    }
    
    // MARK: - XLPagerTabStripChildItem
    func titleForPagerTabStripViewController(pagerTabStripViewController: XLPagerTabStripViewController!) -> String! {
        return self.title
    }
    
    // MARK: - table view methods
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return items.count
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = items[section]
        return section[section.keys.first!]!.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCellWithIdentifier("SessionCell") as! SessionTableViewCell
        
        let section = items[indexPath.section]
        let session = section[section.keys.first!]![indexPath.row]

        cell.titleLabel.text = session[Session.title]        
        cell.speakerLabel.text = session[Speaker.name]
        cell.trackLabel.text = session[Track.track]

        let sessionDate = NSDate(timeIntervalSince1970: Double(session[Session.beginTime]))
        cell.timeLabel.text = dateFormatter.stringFromDate(sessionDate)
        
        let userImage = session[Speaker.photo]?.imageValue ?? UIImage(named: "empty")!
        userImage.asyncToSize(.FillSize(cell.speakerImageView.bounds.size), cornerRadius: cell.speakerImageView.bounds.size.width/2, completion: {result in
            cell.speakerImageView.image = result
        })

        cell.locationLabel.text = session[Location.name]
        
        cell.btnToggleIsFavorite.selected = (find(favorites, session[Session.idColumn]) != nil)
        cell.btnSpeakerIsFavorite.selected = (find(speakerFavorites, session[Speaker.idColumn]) != nil)
        
        cell.indexPath = indexPath
        cell.didSetIsFavoriteTo = {setIsFavorite, indexPath in
            //TODO: update all this to Swift 2.0
            let isInFavorites = find(self.favorites, session[Session.idColumn]) != nil
            if setIsFavorite && !isInFavorites {
                Favorite.saveSessionId(session[Session.idColumn])
            } else if !setIsFavorite && isInFavorites {
                Favorite.removeSessionId(session[Session.idColumn])
            }
            self.notification(kFavoritesChangedNotification, object: nil)
        }
        
        //theme
        cell.titleLabel.textColor = UIColor(hexString: event[Event.mainColor])
        cell.trackLabel.textColor = UIColor(hexString: event[Event.mainColor]).lightenColor(0.1).desaturatedColor()
        cell.speakerLabel.textColor = UIColor.blackColor()
        cell.locationLabel.textColor = UIColor.blackColor()
        
        //check if in the past
        if NSDate().isLaterThanDate(sessionDate) {
            println("\(sessionDate) is in the past")
            cell.titleLabel.textColor = cell.titleLabel.textColor.desaturateColor(0.5).lighterColor()
            cell.trackLabel.textColor = cell.titleLabel.textColor
            cell.speakerLabel.textColor = UIColor.grayColor()
            cell.locationLabel.textColor = UIColor.grayColor()
        }

        return cell
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        let section = items[indexPath.section]
        lastSelectedSession = section[section.keys.first!]![indexPath.row]
        return indexPath
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        lastSelectedSession = nil
    }
    
    var currentSectionIndex: Int? = nil
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        //this section
        let nowSection = items[section]
        var nowSectionTitle = nowSection.keys.first!
        let nowSession = nowSection.values.first!.first!
        let nowSessionStartTime = nowSession[Session.beginTime]
        
        if currentSectionIndex == section - 1 {
            //next upcoming session
            return nowSectionTitle + " (coming up next)"
        }
        
        //next section
        if items.count > section+1 {
            
            let nextSection = items[section+1]
            let nextSession = nextSection.values.first!.first!
            let nextSessionStartTime = nextSession[Session.beginTime]
            
            let rightNow = NSDate().timeIntervalSince1970
            
            if Double(nowSessionStartTime) < rightNow && rightNow < Double(nextSessionStartTime) {
                //current session
                currentSectionIndex = section
                return nowSectionTitle + " (LIVE now)"
            }
        } else {
            //reset the current section index
            currentSectionIndex = nil
        }
        
        return nowSectionTitle
    }
    
    func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return (section == items.count - 1) ?
            /* leave enough space to expand under the tab bar */ ((UIApplication.sharedApplication().windows.first! as! UIWindow).rootViewController as! UITabBarController).tabBar.frame.size.height :
            /* no space between sections */ 0
    }
    
    func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return (section == items.count - 1) ? UIView() : nil
    }
    
    // MARK: - notifications
    func didToggleFavorites() {
        backgroundQueue(loadItems, completion: self.tableView.reloadData)
    }

    func didChangeFavorites() {
        backgroundQueue(loadItems, completion: self.tableView.reloadData)
    }

    func didChangeEventFile() {
        backgroundQueue(loadItems, completion: self.tableView.reloadData)
    }
    
    func scrollToCurrentSession(n: NSNotification) {
        if let dayName = n.userInfo?.values.first as? String where dayName == day.text {

            let now = Int(NSDate().timeIntervalSince1970)
            
            for index in 0 ..< items.count {
                if now < items[index].values.first!.first![Session.beginTime] {
                    mainQueue({
                      if self.items.count > 0 {
                        self.tableView.scrollToRowAtIndexPath(
                            NSIndexPath(forRow: 0, inSection: index),
                            atScrollPosition: UITableViewScrollPosition.Top,
                            animated: true)
                      }
                    })
                    return
                }
            }
        }
    }
    
}
