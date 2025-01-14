//
//  SpeakersViewController.swift
//  Twitter_test
//
//  Created by Marin Todorov on 6/19/15.
//  Copyright (c) 2015 Underplot ltd. All rights reserved.
//

import UIKit
import SQLite

class SpeakersViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var tableView: UITableView!

    let twitter = TwitterController()
    let userCtr = UserController()
    
    var appData: Database {
        return DatabaseProvider.databases[appDataFileName]!
        }

    var database: Database {
        return DatabaseProvider.databases[eventDataFileName]!
    }
    
    typealias SpeakerSection = [String: [Row]]
    
    var items = [SpeakerSection]()
    var filteredItems = [SpeakerSection]()
    
    var favorites = Favorite.allSpeakerFavoriteIDs()
    
    var lastSelectedSpeaker: Row?
    
    var btnFavorites = UIButton()

    var event: Row {
        return (UIApplication.sharedApplication().delegate as! AppDelegate).event
    }

    let searchController = UISearchController(searchResultsController:  nil)
    var initialized = false
    
    //MARK: - view controller
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundQueue(loadSpeakers)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //notifications
        observeNotification(kFavoritesChangedNotification, selector: "didFavoritesChange")
        observeNotification(kDidReplaceEventFileNotification, selector: "didChangeEventFile")
    }

    deinit {
        observeNotification(kFavoritesChangedNotification, selector: nil)
        observeNotification(kDidReplaceEventFileNotification, selector: nil)
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        if let _ = btnFavorites.superview where btnFavorites.hidden == true {
            btnFavorites.hidden = false
        }
        
        if !initialized {
            initialized = true
            
            if items.count == 0 {
                backgroundQueue(loadSpeakers, completion: {
                    self.tableView.reloadData()
                })
            }
            
            //set up the fav button
            btnFavorites.frame = CGRect(x: navigationController!.navigationBar.bounds.size.width - 40, y: 0, width: 40, height: 38)
            
            btnFavorites.setImage(UIImage(named: "like-empty")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate), forState: .Normal)
            btnFavorites.setImage(UIImage(named: "like-full")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate), forState: UIControlState.Selected)
            btnFavorites.addTarget(self, action: Selector("actionToggleFavorites:"), forControlEvents: .TouchUpInside)
            btnFavorites.tintColor = UIColor.whiteColor()
            
            navigationController!.navigationBar.addSubview(btnFavorites)
            
            //add button background
            let gradient = CAGradientLayer()
            gradient.frame = btnFavorites.bounds
            gradient.colors = [UIColor(hexString: event[Event.mainColor]).colorWithAlphaComponent(0.1).CGColor, UIColor(hexString: event[Event.mainColor]).CGColor]
            gradient.locations = [0, 0.25]
            gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
            btnFavorites.layer.insertSublayer(gradient, below: btnFavorites.imageView!.layer)
            
            //search bar
            searchController.searchResultsUpdater = self
            searchController.delegate = self
            searchController.searchBar.delegate = self
            
            searchController.hidesNavigationBarDuringPresentation = false
            searchController.dimsBackgroundDuringPresentation = false
            
            searchController.searchBar.center = CGPoint(
                x: CGRectGetMidX(navigationController!.navigationBar.frame) + 4,
                y: 20) //wtf search controller, just wtf?
            searchController.searchBar.hidden = true
            
            navigationController!.navigationBar.addSubview(
                searchController.searchBar
            )
        }
        
        if count(searchController.searchBar.text) > 0 {
            actionSearch(self)
        }
        
        observeNotification(kTabItemSelectedNotification, selector: "didTapTabItem:")
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        
        //search bar
        didDismissSearchController(searchController)
        
        btnFavorites.hidden = true
        
        observeNotification(kTabItemSelectedNotification, selector: nil)
    }
    
    func didTapTabItem(notification: NSNotification) {
        if let index = notification.userInfo?["object"] as? Int where index == EventBlankTabIndex.Speakers.rawValue {
          let items = isFiltering ? filteredItems : self.items
            mainQueue({
              if items.count > 0 {
                self.tableView.scrollToRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), atScrollPosition: UITableViewScrollPosition.Top, animated: true)
              }
            })
        }
    }

    override func willMoveToParentViewController(parent: UIViewController?) {
        super.willMoveToParentViewController(parent)
        
        //search bar
        if parent == nil {
            searchController.searchBar.removeFromSuperview()
        }
    }
    
    func loadSpeakers() {
        loadSpeakers(nil)
    }
    
    func loadSpeakers(searchTerm: String?) {

        var items = [ScheduleDaySection]()
        
        //load speakers
        var rows = database[SpeakerConfig.tableName].order(Speaker.name).map {$0}
        
        //order and group speakers
        var sectionUsers = [Row]()
        var lastUsedLetter = ""
        
        for speaker in rows {
            let firstNameCharacter = speaker[Speaker.name][0...0].uppercaseString
            
            if lastUsedLetter != "" && lastUsedLetter != firstNameCharacter {
                let newSectionTitle = lastUsedLetter
                let newSection: SpeakerSection = [newSectionTitle: sectionUsers]
                items.append(newSection)
                sectionUsers = []
            }
            
            sectionUsers.append(speaker)
            lastUsedLetter = firstNameCharacter
        }
        
        if sectionUsers.count > 0 {
            let newSectionTitle = lastUsedLetter
            let newSection: ScheduleDaySection = [newSectionTitle: sectionUsers]
            items.append(newSection)
        }
        
        if self.tableView != nil {
            mainQueue({
                if self.items.count == 0 {
                    self.tableView.hidden = true
                    self.view.addSubview(MessageView(text: "You currently have no favorited speakers"))
                } else {
                    self.tableView.hidden = false
                    MessageView.removeViewFrom(self.view)
                }
            })
        }
        
        self.items = items
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if let speakerDetails = segue.destinationViewController as? SpeakerDetailsViewController {
            speakerDetails.speaker = lastSelectedSpeaker
            speakerDetails.favorites = favorites
        }
        
        searchController.searchBar.endEditing(true)
    }
    
    //MARK: - table view methods
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        let items = isFiltering ? filteredItems : self.items
        
        return items.count
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let items = isFiltering ? filteredItems : self.items
        
        let section = items[section]
        return section[section.keys.first!]!.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let items = isFiltering ? filteredItems : self.items
        
        let cell = self.tableView.dequeueReusableCellWithIdentifier("SpeakerCell") as! SpeakerCell
        
        //eg guard
        if indexPath.section >= items.count {
            return cell
        }
        
        let section = items[indexPath.section]
        let row = section[section.keys.first!]![indexPath.row]
        
        let userImage = row[Speaker.photo]?.imageValue ?? UIImage(named: "empty")!
        userImage.asyncToSize(.FillSize(cell.userImage.bounds.size), cornerRadius: cell.userImage.bounds.size.width/2, completion: {result in
            cell.userImage.image = result
        })
        
        cell.nameLabel.text = row[Speaker.name]
        if let twitter = row[Speaker.twitter] where count(twitter) > 0 {
            cell.twitterLabel.text = twitter.hasPrefix("@") ? twitter : "@"+twitter
        } else {
            cell.twitterLabel.text = ""
        }
        cell.btnToggleIsFavorite.selected = (find(favorites, row[Speaker.idColumn]) != nil)
        
        if row[Speaker.photo]?.imageValue == nil {
            userCtr.lookupUserImage(row, completion: {userImage in
                userImage?.asyncToSize(.FillSize(cell.userImage.bounds.size), cornerRadius: cell.userImage.bounds.size.width/2, completion: {result in
                    cell.userImage.image = result
                })
            })
        }
        
        cell.indexPath = indexPath
        cell.didSetIsFavoriteTo = {setIsFavorite, indexPath in
            //TODO: update all this to Swift 2.0
            let isInFavorites = find(self.favorites, row[Speaker.idColumn]) != nil
            if setIsFavorite && !isInFavorites {
                self.favorites.append(row[Speaker.idColumn])
                Favorite.saveSessionId(row[Speaker.idColumn])
            } else if !setIsFavorite && isInFavorites {
                self.favorites.removeAtIndex(find(self.favorites, row[Speaker.idColumn])!)
                Favorite.removeSessionId(row[Speaker.idColumn])
            }
        }
        
        return cell
    }

    func tableView(tableView: UITableView, willSelectRowAtIndexPath indexPath: NSIndexPath) -> NSIndexPath? {
        let items = isFiltering ? filteredItems : self.items
        
        let section = items[indexPath.section]
        lastSelectedSpeaker = section[section.keys.first!]![indexPath.row]
        return indexPath
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)
        lastSelectedSpeaker = nil
    }
    
    func sectionIndexTitlesForTableView(tableView: UITableView) -> [AnyObject]! {
        let items = isFiltering ? filteredItems : self.items
        
        if items.count < 4 {
            return []
        } else {
            return items.map {$0.keys.first!}
        }
    }
    
    //MARK: - favorites
    func didFavoritesChange() {
        backgroundQueue({
            self.favorites = Favorite.allSpeakerFavoriteIDs()
            self.filterItemsWithTerm(nil, favorites: self.btnFavorites.selected)
        },
        completion: { self.tableView.reloadData() })
    }
    
    //notifications
    func didChangeEventFile() {
        backgroundQueue(loadSpeakers, completion: {
            self.navigationController?.popToRootViewControllerAnimated(true)
            self.tableView.reloadData()
        })
    }
    
    func actionToggleFavorites(sender: AnyObject) {
        btnFavorites.selected = !btnFavorites.selected
      
        self.notification(kFavoritesToggledNotification, object: nil)

        let message = alert(btnFavorites.selected ? "Showing favorite speakers only" : "Showing all speakers", buttons: [], completion: nil)
        delay(seconds: 1.0, {
            message.dismissViewControllerAnimated(true, completion: nil)
        })
        
        btnFavorites.animateSelect(scale: 0.8, completion: nil)
        
        backgroundQueue({ self.filterItemsWithTerm(nil, favorites: self.btnFavorites.selected) },
            completion: { self.tableView.reloadData() })
    }

}

extension SpeakersViewController: UISearchControllerDelegate, UISearchResultsUpdating, UISearchBarDelegate {

    //how can a single class be so broken @UISearchController?
    
    @IBAction func actionSearch(sender: AnyObject) {
        searchController.searchBar.hidden = false
        
        btnFavorites.hidden = true
        navigationItem.leftBarButtonItem = nil
        
        searchController.searchBar.becomeFirstResponder()
    }
    
    func didDismissSearchController(searchController: UISearchController) {
        searchController.searchBar.hidden = true
        
        self.btnFavorites.hidden = false
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Search, target: self, action: "actionSearch:")
    }
    
    func showSearchBar() {
        UIView.animateWithDuration(0.33, delay: 0, options: nil, animations: {
            self.searchController.searchBar.alpha = 1
            }, completion: nil)
    }
    
    func hideSearchBar(completion: (()->Void)? = nil) {
        UIView.animateWithDuration(0.33, delay: 0, options: nil, animations: {
            self.searchController.searchBar.alpha = 0
            }, completion: nil)
    }
    
    func filterItemsWithTerm(term: String?, favorites: Bool = false) {
        var results = [Row]()
        for section in items {
            for row in section.values.first! {
                var eligibleResult = true
                if favorites {
                    if find(self.favorites, row[Speaker.idColumn]) == nil {
                        eligibleResult = false
                    }
                }
                if let term = term {
                    if !(row[Speaker.name]).contains(term, ignoreCase: true) {
                        eligibleResult = false
                    }
                }
                if eligibleResult {
                    results.append(row)
                }
            }
        }
        let searchSection: SpeakerSection = ["search": results]
        filteredItems = [searchSection]
    }
    
    var isFiltering: Bool {
        let result = count(searchController.searchBar.text) > 0 || self.btnFavorites.selected
        return result
    }
    
    //search controller
    func updateSearchResultsForSearchController(searchController: UISearchController) {
        backgroundQueue({ self.filterItemsWithTerm(searchController.searchBar.text, favorites: self.btnFavorites.selected) },
            completion: { self.tableView.reloadData() })
    }
}


