#include "multicore_menu.hpp"
#include "native_vgui.hpp"
#include <windows.h>
#include <bcrypt.h>
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstring>

namespace gmodrp {
namespace {
using Method = void(*)(void*);
Method originalApply = nullptr, originalReset = nullptr;
void* applyAddress = nullptr; void* resetAddress = nullptr;
char* image = nullptr;
bool applyCreated = false, resetCreated = false, installed = false, poisoned = false;
std::atomic<bool> active{false}, actual{false}, actualKnown{false};
std::atomic<int> pending{-1};
std::atomic<unsigned> callbacks{0};
using renderer::native::Call;
struct CallbackScope {
    CallbackScope() { ++callbacks; }
    ~CallbackScope() { --callbacks; }
};
std::string HashFile(const wchar_t* path) {
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr; std::string out;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0
        && BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0) {
        std::array<unsigned char, 65536> buffer{}; DWORD count = 0; bool okay = true;
        for (;;) {
            if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &count, nullptr)) { okay = false; break; }
            if (!count) break;
            if (BCryptHashData(hash, buffer.data(), count, 0) < 0) { okay = false; break; }
        }
        std::array<unsigned char, 32> digest{};
        if (okay && BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0) {
            constexpr char hex[] = "0123456789ABCDEF";
            for (const auto byte : digest) { out += hex[byte >> 4]; out += hex[byte & 15]; }
        }
    }
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file); return out;
}
void* Multicore(void* dialog) {
    if (!dialog || !image) return nullptr;
    const auto combo = reinterpret_cast<void*(*)(void*, const char*, bool)>(image + 0x6bbc0)(dialog, "Multicore", false);
    return combo && Call<int>(combo, 0x908) == 2 ? combo : nullptr;
}
void OnApply(void* dialog) {
    CallbackScope scope;
    int choice = -1;
    if (active.load()) {
        if (auto combo = Multicore(dialog)) choice = reinterpret_cast<int(*)(void*)>(image + 0x8ce60)(combo);
    }
    originalApply(dialog);
    // Do not enter Lua or write configuration within an engine callback.
    if (active.load() && (choice == 0 || choice == 1)) pending.store(choice);
}
void OnReset(void* dialog) {
    CallbackScope scope;
    originalReset(dialog);
    if (active.load() && actualKnown.load()) {
        if (auto combo = Multicore(dialog)) Call<void>(combo, 0x950, actual.load() ? 1 : 0);
    }
}
bool DisableAndRemove() noexcept {
    bool disabled = true;
    auto disable = [&](bool created, void* address) {
        if (!created) return;
        const auto status = MH_DisableHook(address);
        if (status != MH_OK && status != MH_ERROR_DISABLED) disabled = false;
    };
    disable(applyCreated, applyAddress); disable(resetCreated, resetAddress);
    if (!disabled || callbacks.load() != 0) { poisoned = true; return false; }
    auto remove = [&](bool& created, void* address) {
        if (created) { if (MH_RemoveHook(address) == MH_OK) created = false; else poisoned = true; }
    };
    remove(applyCreated, applyAddress); remove(resetCreated, resetAddress);
    return !applyCreated && !resetCreated;
}
}
bool InstallMulticoreMenu(std::string& error) noexcept {
    try {
        error.clear(); if (installed) return true;
        if (poisoned) { error = "Native multicore hook cleanup failed; restart the client"; return false; }
        const auto module = GetModuleHandleW(L"GameUI.dll");
        if (!module) { error = "GameUI is not loaded"; return false; }
        wchar_t path[32768]{};
        if (!GetModuleFileNameW(module, path, 32768)
            || HashFile(path) != "E06A042C4284CBCDF32DFEB60CDEA092CE934433D3BBABC24F3DCCA2E103B27D") {
            error = "Unsupported GameUI build; native multicore adapter disabled"; return false;
        }
        image = reinterpret_cast<char*>(module);
        // These exact methods/offsets are reused from the prior verified native
        // menu adapter. Check mapped entry bytes as well as the full file hash.
        constexpr unsigned char applyBytes[]{0x4c,0x8b,0xdc,0x49,0x89,0x7b,0x20,0x55,0x49,0x8d,0x6b,0xb8};
        constexpr unsigned char resetBytes[]{0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x74,0x24,0x18};
        if (std::memcmp(image + 0x1a250, applyBytes, sizeof(applyBytes))
            || std::memcmp(image + 0x1b900, resetBytes, sizeof(resetBytes))) {
            error = "Native multicore entry points were modified; adapter disabled"; return false;
        }
        // Keep callback code/trampolines resident even if external hook removal
        // fails. Never uninitialize MinHook owned by another module.
        HMODULE pinned = nullptr;
        if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(&OnApply), &pinned)
            || !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                reinterpret_cast<LPCWSTR>(module), &pinned)) {
            error = "Native multicore callback lifetime could not be pinned"; return false;
        }
        const auto init = MH_Initialize();
        if (init != MH_OK && init != MH_ERROR_ALREADY_INITIALIZED) { error = "Native multicore hook initialization failed"; return false; }
        applyAddress = image + 0x1a250; resetAddress = image + 0x1b900;
        auto status = MH_CreateHook(applyAddress, reinterpret_cast<void*>(&OnApply), reinterpret_cast<void**>(&originalApply));
        if (status == MH_OK) {
            applyCreated = true;
            status = MH_CreateHook(resetAddress, reinterpret_cast<void*>(&OnReset), reinterpret_cast<void**>(&originalReset));
            if (status == MH_OK) resetCreated = true;
        }
        if (status == MH_OK) status = MH_EnableHook(applyAddress);
        if (status == MH_OK) status = MH_EnableHook(resetAddress);
        if (status != MH_OK) {
            active = false; DisableAndRemove();
            error = "Native multicore hook installation failed"; return false;
        }
        pending = -1; installed = true; active = true; return true;
    } catch (...) { active = false; DisableAndRemove(); error = "Native multicore adapter initialization failed"; return false; }
}
void UninstallMulticoreMenu() noexcept {
    active = false; pending = -1; DisableAndRemove(); installed = false;
}
int PollMulticoreMenu() noexcept { return pending.exchange(-1); }
void SetMulticoreMenuActualState(bool enabled) noexcept { actual = enabled; actualKnown = true; }
}
