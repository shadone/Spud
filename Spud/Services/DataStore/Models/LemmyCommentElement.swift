//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit

@objc(LemmyCommentElement) public final class LemmyCommentElement: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<LemmyCommentElement> {
        NSFetchRequest<LemmyCommentElement>(entityName: "CommentElement")
    }

    @nonobjc public class func fetchForDeletion(
        postObjectId: NSManagedObjectID,
        sortType: CommentSortType
    ) -> NSFetchRequest<LemmyCommentElement> {
        let request = NSFetchRequest<LemmyCommentElement>(entityName: "CommentElement")
        request.predicate = NSPredicate(
            format: "post == %@ && sortTypeRawValue == %@",
            postObjectId, sortType.rawValue
        )
        request.includesPropertyValues = false
        return request
    }

    // MARK: Properties

    /// Specifies how deep this comment is nested.
    @NSManaged public var depth: Int16

    /// Index of the comment for presentation in order.
    @NSManaged public var index: Int64

    /// See ``sortType``.
    @NSManaged public var sortTypeRawValue: String

    /// See ``moreChildCount``.
    @NSManaged public var moreChildCountRawValue: NSNumber?

    /// See ``moreParentId``.
    @NSManaged public var moreParentIdRawValue: NSNumber?

    // MARK: Relations

    @NSManaged public var comment: LemmyComment?
    @NSManaged public var post: LemmyPost
}

extension LemmyCommentElement {
    /// Comment sort order.
    var sortType: CommentSortType {
        get {
            CommentSortType(rawValue: sortTypeRawValue) ?? .hot
        }
        set {
            sortTypeRawValue = newValue.rawValue
        }
    }

    /// The number of child comments that could be fetched for this "More element.
    var moreChildCount: Int32? {
        get {
            moreChildCountRawValue.map(\.int32Value)
        }
        set {
            moreChildCountRawValue = newValue.map { NSNumber(value: $0) }
        }
    }

    /// The local comment identifier that is the parent comment for this "More" element.
    var moreParentId: Int32? {
        get {
            moreParentIdRawValue.map(\.int32Value)
        }
        set {
            moreParentIdRawValue = newValue.map { NSNumber(value: $0) }
        }
    }
}
