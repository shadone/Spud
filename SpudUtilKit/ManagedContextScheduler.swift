//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation

// Heavily inspired by
// https://github.com/pointfreeco/combine-schedulers/blob/afc84b6a3639198b7b8b6d79f04eb3c2ee590d29/Sources/CombineSchedulers/ImmediateScheduler.swift
public struct ManagedContextScheduler<SchedulerTimeType, SchedulerOptions>: Scheduler
    where SchedulerTimeType: Strideable,
    SchedulerTimeType.Stride: SchedulerTimeIntervalConvertible
{
    public var now: SchedulerTimeType

    public var minimumTolerance: SchedulerTimeType.Stride = .zero

    let managedObjectContext: NSManagedObjectContext

    init(_ managedObjectContext: NSManagedObjectContext, now: SchedulerTimeType) {
        self.managedObjectContext = managedObjectContext
        self.now = now
    }

    public func schedule(options _: SchedulerOptions?, _ action: @escaping () -> Void) {
        managedObjectContext.perform {
            action()
        }
    }

    public func schedule(after _: SchedulerTimeType, interval _: SchedulerTimeType.Stride, tolerance _: SchedulerTimeType.Stride, options _: SchedulerOptions?, _ action: @escaping () -> Void) -> Cancellable {
        assertionFailure("future scheduling is not implemented")
        action()
        return AnyCancellable { }
    }

    public func schedule(after _: SchedulerTimeType, tolerance _: SchedulerTimeType.Stride, options _: SchedulerOptions?, _ action: @escaping () -> Void) {
        assertionFailure("future scheduling is not implemented")
        action()
    }
}

public extension Scheduler
    where
    SchedulerTimeType == DispatchQueue.SchedulerTimeType,
    SchedulerOptions == DispatchQueue.SchedulerOptions
{
    static func managedContentScheduler(_ managedObjectContext: NSManagedObjectContext) -> ManagedContextSchedulerOf<Self> {
        // NB: `DispatchTime(uptimeNanoseconds: 0) == .now())`. Use `1` for consistency.
        ManagedContextScheduler(managedObjectContext, now: SchedulerTimeType(DispatchTime(uptimeNanoseconds: 1)))
    }
}

/// A convenience type to specify an `ImmediateTestScheduler` by the scheduler it wraps rather than
/// by the time type and options type.
public typealias ManagedContextSchedulerOf<Scheduler> = ManagedContextScheduler<
    Scheduler.SchedulerTimeType, Scheduler.SchedulerOptions
> where Scheduler: Combine.Scheduler
