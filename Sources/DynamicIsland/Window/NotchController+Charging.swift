import AppKit

extension NotchController {

    func setupCharging() {
        power.onPlugChange = { [weak self] pluggedIn in
            guard let self else { return }
            self.chargingClearWork?.cancel()
            if pluggedIn {
                self.state.chargingFlourish = self.power.level
                // Auto-dismiss the flourish after a few seconds.
                let work = DispatchWorkItem { [weak self] in self?.state.chargingFlourish = nil }
                self.chargingClearWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            } else {
                self.state.chargingFlourish = nil
            }
        }
        power.start()
    }
}
