import Foundation

enum SampleBlocks {
    static let defaults: [BlockDefinition] = [
        BlockDefinition(
            name: "Command Interaction [Event]",
            description: "When a command is executed, this event will trigger.",
            category: "Events",
            autoExecute: true,
            inputs: [],
            options: [
                BlockOption(
                    id: "command_name",
                    name: "Command Name",
                    description: "The command name to listen for.",
                    type: .text,
                    choices: [:]
                )
            ],
            outputs: [
                BlockPort(id: "action", name: "Action", description: "Executes the next blocks.", types: [.action], required: false, direction: .output),
                BlockPort(id: "interaction", name: "Interaction", description: "The Discord interaction.", types: [.object], required: false, direction: .output)
            ],
            sourceFile: "command_interaction_event.js"
        ),
        BlockDefinition(
            name: "Send Message",
            description: "Sends a message.",
            category: "Message Stuff",
            autoExecute: false,
            inputs: [
                BlockPort(id: "action", name: "Action", description: "Executes this block.", types: [.action], required: false, direction: .input),
                BlockPort(id: "channel", name: "Channel", description: "The text channel or DM channel.", types: [.object, .unspecified], required: true, direction: .input),
                BlockPort(id: "text", name: "Text", description: "Message content.", types: [.text, .unspecified], required: false, direction: .input)
            ],
            options: [
                BlockOption(id: "silent", name: "Silent Message", description: "Suppress notifications.", type: .select, choices: ["undefined": "False", "true": "True"])
            ],
            outputs: [
                BlockPort(id: "action", name: "Action", description: "Executes the next blocks.", types: [.action], required: false, direction: .output),
                BlockPort(id: "message", name: "Message", description: "The sent message.", types: [.object], required: false, direction: .output)
            ],
            sourceFile: "send_message.js"
        ),
        BlockDefinition(
            name: "Merge Texts",
            description: "Merges two texts into a single text.",
            category: "Extras",
            autoExecute: false,
            inputs: [
                BlockPort(id: "action", name: "Action", description: "Executes this block.", types: [.action], required: false, direction: .input),
                BlockPort(id: "text1", name: "Text 1", description: "First text.", types: [.text, .unspecified], required: true, direction: .input),
                BlockPort(id: "text2", name: "Text 2", description: "Second text.", types: [.text, .unspecified], required: true, direction: .input)
            ],
            options: [
                BlockOption(id: "position_type", name: "Position Type", description: "Where to merge text.", type: .select, choices: ["first": "First Position", "last": "Last Position"])
            ],
            outputs: [
                BlockPort(id: "action", name: "Action", description: "Executes the next blocks.", types: [.action], required: false, direction: .output),
                BlockPort(id: "text", name: "Text", description: "Merged text.", types: [.text], required: false, direction: .output)
            ],
            sourceFile: "merge_texts.js"
        )
    ]
}
