//
//  SessionDetailsCell.swift
//  EventBlank
//
//  Created by Marin Todorov on 6/25/15.
//  Copyright (c) 2015 Underplot ltd. All rights reserved.
//

import UIKit

class SessionDetailsCell: UITableViewCell, UITextViewDelegate {
    
    @IBOutlet weak var userImage: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var twitterLabel: UILabel!
    @IBOutlet weak var websiteLabel: UILabel!
    @IBOutlet weak var btnToggleIsFavorite: UIButton!
    @IBOutlet weak var descriptionTextView: UITextView!
    @IBOutlet weak var sessionTitleLabel: UILabel!
    @IBOutlet weak var trackTitleLabel: UILabel!
    
    var indexPath: NSIndexPath?
    var didSetIsFavoriteTo: ((Bool, NSIndexPath)->Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        btnToggleIsFavorite.setImage(UIImage(named: "like-full")?.imageWithRenderingMode(.AlwaysTemplate), forState: .Selected)
        
        twitterLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: Selector("actionTapTwitter")))
        websiteLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: Selector("actionTapURL")))
        
        descriptionTextView.delegate = self
    }
    
    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
    }
    
    @IBAction func actionToggleIsFavorite(sender: AnyObject) {
        btnToggleIsFavorite.selected = !btnToggleIsFavorite.selected
        didSetIsFavoriteTo!(btnToggleIsFavorite.selected, indexPath!)
        return
    }
    
    var didTapTwitter: (()->Void)?
    var didTapURL: (()->Void)?
    
    func actionTapTwitter() {
        didTapTwitter?()
    }
    
    func actionTapURL() {
        didTapURL?()
    }
}