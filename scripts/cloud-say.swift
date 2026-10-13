// Sends a phrase to a Debug build of My Cloud as if spoken after "Ei Cloud".
// Usage: swift scripts/cloud-say.swift "que dia é hoje?"
import Foundation
let phrase = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("mycloud.debug.command"), object: phrase, userInfo: nil, deliverImmediately: true)
