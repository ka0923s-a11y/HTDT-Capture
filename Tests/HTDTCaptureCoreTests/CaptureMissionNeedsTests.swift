import Foundation
import Testing
@testable import HTDTCaptureCore

// legacy bolph71656-ai/HTDT-Capture#364 §4: "This capture needs" — mission intent itemized in
// operator vocabulary: counts and optional flags, never raw schema
// identifiers.

@Test
func generalCaptureNeedsOnlyRoomGeometry() {
    let needs = CaptureMissionNeeds.needs(
        for: CaptureTaskProfile.geometryOnly
    )
    #expect(needs == [CaptureMissionNeeds.roomGeometry])
}

@Test
func roomAndListeningProfileListsListeningPosition() {
    let needs = CaptureMissionNeeds.needs(
        for: CaptureTaskProfile.roomAndListeningPosition
    )
    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .annotationEntity,
            title: "Listening position",
            count: 1,
            isOptional: false
        )
    ))
}

@Test
func theaterProfileItemizesRolesAndMergesAlternatives() {
    let profile = CaptureTaskProfile.theaterLayout(
        speakerRoles: ["L", "C", "R"],
        subwooferCount: 1
    )
    let needs = CaptureMissionNeeds.needs(for: profile)

    #expect(needs.contains {
        $0.kind == .annotationEntity
            && $0.title == "Listening position"
    })
    // The screen-presence alternative group merges into one row.
    #expect(needs.contains {
        $0.title == "Display or Projection screen"
    })
    #expect(!needs.contains { $0.title == "Display" })
    let speakerNeeds = needs.filter { $0.kind == .speakerRole }
    #expect(speakerNeeds.count == 4)
    #expect(speakerNeeds.contains { $0.title == "Speaker — L" })
    #expect(speakerNeeds.contains { $0.title == "Speaker — LFE" })
    // Never a raw schema identifier.
    #expect(!needs.contains { $0.title.contains("_") })
}

@Test
func layoutProfileResolvesRoleNamesThroughVocabulary() {
    let profile = CaptureTaskProfile.layoutProfile(
        SpeakerLayoutProfiles.stereo
    )
    let needs = CaptureMissionNeeds.needs(for: profile)
    // Built-in role IDs resolve to their display names (legacy bolph71656-ai/HTDT-Capture#315).
    #expect(needs.contains { $0.title == "Speaker — Front left" })
    #expect(needs.contains { $0.title == "Speaker — Front right" })
}

// legacy bolph71656-ai/HTDT-Capture#426: the "Theater layout" preset derives its requirements from a
// `SpeakerLayoutProfile` vocabulary, so every `speaker_role_<roleID>`
// identifier names a role ID the `role_binding` picker can select —
// setup and the annotation workspace share the one token set.
@Test
func theaterPresetRequirementsComeFromLayoutProfileVocabulary() {
    let vocabulary = SpeakerLayoutProfiles.surround7_1_4
    let profile = CaptureTaskProfile.theaterLayout

    let roleRequirements = profile.requirements.filter {
        $0.identifier.hasPrefix("speaker_role_")
    }
    let expectedRoles = vocabulary.roles.filter { !$0.isSubwoofer }
    #expect(roleRequirements.count == expectedRoles.count)
    for requirement in roleRequirements {
        let roleID = String(
            requirement.identifier.dropFirst("speaker_role_".count)
        )
        #expect(requirement.match.kind == .annotationChannelRole)
        #expect(requirement.match.value == roleID)
        #expect(vocabulary.roleDefinition(roleID: roleID) != nil)
    }

    // The subwoofer requirement follows the profile's sub
    // cardinality, and the MLP + screen-presence requirements stay.
    #expect(
        profile.requirements.contains {
            $0.identifier == "subwoofers" && $0.minimumCount == 1
        }
    )
    #expect(
        profile.requirements.contains {
            $0.identifier == "primary_listening_position"
        }
    )
    #expect(profile.identifier == "theater_layout")
    #expect(profile.title == "Theater layout")
}

@Test
func taskPlanNeedsAggregateCountedRows() throws {
    let plan = try HTDTCaptureTaskPlan(
        planID: "plan-1",
        planVersion: "1.0.0",
        projectRef: "proj-1",
        roomName: "Studio",
        entityChecklist: [
            try HTDTTaskPlanEntityItem(
                itemID: "sp-l",
                entityType: .speaker,
                requirement: .required,
                channelRole: .left
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "sp-r",
                entityType: .speaker,
                requirement: .required,
                channelRole: .right
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "mlp",
                entityType: .listeningPosition,
                requirement: .required
            ),
            try HTDTTaskPlanEntityItem(
                itemID: "sub",
                entityType: .subwoofer,
                requirement: .optional,
                channelRole: .lfe1
            ),
        ],
        measurementRequests: [
            try HTDTTaskPlanMeasurementItem(
                itemID: "m1",
                quantityType: "room_width",
                requirement: .required
            ),
            try HTDTTaskPlanMeasurementItem(
                itemID: "m2",
                quantityType: "room_width",
                requirement: .required
            ),
        ]
    )
    let needs = CaptureMissionNeeds.needs(for: plan)

    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .annotationEntity,
            title: "Speaker — L",
            count: 1,
            isOptional: false
        )
    ))
    #expect(needs.contains {
        $0.title == "Listening position" && !$0.isOptional
    })
    #expect(needs.contains {
        $0.title == "Subwoofer — LFE1" && $0.isOptional
    })
    #expect(needs.contains(
        CaptureMissionNeed(
            kind: .measurement,
            title: "Room Width",
            count: 2,
            isOptional: false
        )
    ))
    // Item IDs never leak into operator vocabulary.
    #expect(!needs.contains {
        $0.title.contains("sp-") || $0.title.contains("mlp")
    })
}

@Test
func humanizedTokenSplitsUnderscores() {
    #expect(
        CaptureMissionNeeds.humanizedToken("FRONT_LEFT")
            == "Front Left"
    )
    #expect(CaptureMissionNeeds.humanizedToken("LFE1") == "LFE1")
    #expect(CaptureMissionNeeds.humanizedToken("L") == "L")
}
