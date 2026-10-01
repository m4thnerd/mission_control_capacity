import CapacityCore
import SwiftUI

enum MissionEditor: Identifiable {
    case task(MissionTask)
    case project(MissionProject)
    case objective(MissionObjective)

    var id: UUID {
        switch self {
        case .task(let task): task.id
        case .project(let project): project.id
        case .objective(let objective): objective.id
        }
    }
}

struct MissionEditorSheet: View {
    let editor: MissionEditor
    @ObservedObject var missions: MissionStore

    var body: some View {
        switch editor {
        case .task(let task): TaskEditor(draft: task, missions: missions)
        case .project(let project): ProjectEditor(draft: project, missions: missions)
        case .objective(let objective): ObjectiveEditor(draft: objective, missions: missions)
        }
    }
}

/// Form chrome shared by the editors: title, fields, and Delete/Cancel/Save.
private struct EditorForm<Fields: View>: View {
    let title: String
    let canSave: Bool
    let onDelete: (() -> Void)?
    let onSave: () -> Void
    @ViewBuilder let fields: Fields
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Cockpit.label(20, .semibold)).kerning(3)
            Form { fields }
                .formStyle(.grouped)
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct TaskEditor: View {
    @State var draft: MissionTask
    @ObservedObject var missions: MissionStore
    @State private var hasDue: Bool

    init(draft: MissionTask, missions: MissionStore) {
        _draft = State(initialValue: draft)
        _hasDue = State(initialValue: draft.due != nil)
        self.missions = missions
    }

    private var isNew: Bool { !missions.board.tasks.contains { $0.id == draft.id } }

    var body: some View {
        EditorForm(
            title: isNew ? "NEW TASK" : "EDIT TASK",
            canSave: !draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onDelete: isNew ? nil : { missions.delete(draft) }
        ) {
            var saved = draft
            saved.title = saved.title.trimmingCharacters(in: .whitespaces)
            saved.due = hasDue ? (saved.due ?? Date()) : nil
            missions.upsert(saved)
        } fields: {
            TextField("Task", text: $draft.title)
            Picker("Project", selection: $draft.projectID) {
                Text("None").tag(UUID?.none)
                ForEach(missions.board.projects) { project in
                    Text(project.name).tag(UUID?.some(project.id))
                }
            }
            Picker("Switch bank", selection: $draft.bucket) {
                ForEach(TaskBucket.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Due date", isOn: $hasDue)
            if hasDue {
                DatePicker(
                    "Due",
                    selection: Binding(get: { draft.due ?? Date() }, set: { draft.due = $0 }),
                    displayedComponents: .date
                )
            }
        }
    }
}

private struct ProjectEditor: View {
    @State var draft: MissionProject
    @ObservedObject var missions: MissionStore

    private static let phases = ["Idea", "Design", "Build", "Beta", "Launch", "Live", "Paused"]
    private var isNew: Bool { !missions.board.projects.contains { $0.id == draft.id } }

    var body: some View {
        EditorForm(
            title: isNew ? "NEW PROJECT" : "EDIT PROJECT",
            canSave: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty,
            onDelete: isNew ? nil : { missions.delete(draft) }
        ) {
            var saved = draft
            saved.name = saved.name.trimmingCharacters(in: .whitespaces)
            missions.upsert(saved)
        } fields: {
            TextField("Name", text: $draft.name)
            Picker("Phase", selection: $draft.phase) {
                ForEach(Self.phases + (Self.phases.contains(draft.phase) ? [] : [draft.phase]), id: \.self) {
                    Text($0).tag($0)
                }
            }
            LabeledContent("Progress") {
                HStack {
                    Slider(value: $draft.progress, in: 0...100, step: 5)
                    Text("\(Int(draft.progress))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            TextField("Next action", text: $draft.nextAction)
        }
    }
}

private struct ObjectiveEditor: View {
    @State var draft: MissionObjective
    @ObservedObject var missions: MissionStore
    @State private var periodTitle: String

    init(draft: MissionObjective, missions: MissionStore) {
        _draft = State(initialValue: draft)
        _periodTitle = State(initialValue: missions.board.periodTitle)
        self.missions = missions
    }

    private var isNew: Bool { !missions.board.objectives.contains { $0.id == draft.id } }

    var body: some View {
        EditorForm(
            title: isNew ? "NEW OBJECTIVE" : "EDIT OBJECTIVE",
            canSave: !draft.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onDelete: isNew ? nil : { missions.delete(draft) }
        ) {
            var saved = draft
            saved.title = saved.title.trimmingCharacters(in: .whitespaces)
            saved.keyResultsOnTrack = min(saved.keyResultsOnTrack, saved.keyResultsTotal)
            missions.upsert(saved)
            let period = periodTitle.trimmingCharacters(in: .whitespaces)
            if !period.isEmpty, period != missions.board.periodTitle {
                missions.setPeriodTitle(period)
            }
        } fields: {
            TextField("Objective", text: $draft.title)
            LabeledContent("Progress") {
                HStack {
                    Slider(value: $draft.progress, in: 0...100, step: 5)
                    Text("\(Int(draft.progress))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Stepper("Key results: \(draft.keyResultsTotal)", value: $draft.keyResultsTotal, in: 0...8)
            if draft.keyResultsTotal > 0 {
                Stepper(
                    "On track: \(min(draft.keyResultsOnTrack, draft.keyResultsTotal))",
                    value: $draft.keyResultsOnTrack,
                    in: 0...draft.keyResultsTotal
                )
            }
            TextField("Note", text: $draft.note, prompt: Text("Shown when there are no key results"))
            TextField("Period (all objectives)", text: $periodTitle)
        }
    }
}
