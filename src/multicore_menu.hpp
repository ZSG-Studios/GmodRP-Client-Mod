#pragma once
#include <string>
namespace gmodrp {
// Hooks only the pinned native Video Advanced dialog Apply/Reset methods.
bool InstallMulticoreMenu(std::string& error) noexcept;
void UninstallMulticoreMenu() noexcept;
// Latest explicit Apply selection, consumed once. -1 means no request.
int PollMulticoreMenu() noexcept;
// Cached actual profile state, used only when the engine resets the dialog.
void SetMulticoreMenuActualState(bool enabled) noexcept;
}
