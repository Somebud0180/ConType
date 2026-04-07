import Testing
@testable import ConType

@MainActor
struct ConTypeTests {

    @Test func moveWrapsOnDiscretePressAtEdges() {
        let viewModel = KeyboardOverlayViewModel()

        let movedLeft = viewModel.move(.left, trigger: .press)
        #expect(movedLeft)
        #expect(viewModel.selectedColumn == viewModel.rows[viewModel.selectedRow].count - 1)

        let movedUp = viewModel.move(.up, trigger: .press)
        #expect(movedUp)
        #expect(viewModel.selectedRow == viewModel.rows.count - 1)
        #expect(viewModel.selectedColumn == viewModel.rows[viewModel.selectedRow].count - 1)
    }

    @Test func moveDoesNotWrapOnHoldRepeatAtEdges() {
        let viewModel = KeyboardOverlayViewModel()

        let movedLeft = viewModel.move(.left, trigger: .holdRepeat)
        #expect(!movedLeft)
        #expect(viewModel.selectedRow == 0)
        #expect(viewModel.selectedColumn == 0)

        let movedUp = viewModel.move(.up, trigger: .holdRepeat)
        #expect(!movedUp)
        #expect(viewModel.selectedRow == 0)
        #expect(viewModel.selectedColumn == 0)
    }

    @Test func shiftShortcutCyclesWithAndWithoutCapsLockStep() {
        let viewModel = KeyboardOverlayViewModel()

        viewModel.cycleShiftShortcut(cyclesToCapsLock: true)
        #expect(viewModel.isModifierActive(.shift))
        #expect(!viewModel.isModifierActive(.capsLock))

        viewModel.cycleShiftShortcut(cyclesToCapsLock: true)
        #expect(!viewModel.isModifierActive(.shift))
        #expect(viewModel.isModifierActive(.capsLock))

        viewModel.cycleShiftShortcut(cyclesToCapsLock: true)
        #expect(!viewModel.isModifierActive(.shift))
        #expect(!viewModel.isModifierActive(.capsLock))

        viewModel.cycleShiftShortcut(cyclesToCapsLock: false)
        #expect(viewModel.isModifierActive(.shift))
        #expect(!viewModel.isModifierActive(.capsLock))

        viewModel.cycleShiftShortcut(cyclesToCapsLock: false)
        #expect(!viewModel.isModifierActive(.shift))
        #expect(!viewModel.isModifierActive(.capsLock))
    }
}
