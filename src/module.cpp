#include <GarrysMod/Lua/Interface.h>
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <string>
#include <filesystem>
#include <stdexcept>
#include "multicore_profile.hpp"
#include "multicore_menu.hpp"

namespace {
bool menuAvailable = false;
std::string menuError;
LUA_FUNCTION_STATIC(PollGraphicsMenu) {
    gmodrp::SetMulticoreMenuActualState(LUA->GetBool(1));
    LUA->CreateTable();
    LUA->PushBool(menuAvailable); LUA->SetField(-2, "available");
    LUA->PushNumber(menuAvailable ? gmodrp::PollMulticoreMenu() : -1); LUA->SetField(-2, "request");
    LUA->PushString(menuError.c_str()); LUA->SetField(-2, "error"); return 1;
}
std::string HashFile(const wchar_t* path) {
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_HASH_HANDLE hash = nullptr;
    std::string result;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0
        && BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0) {
        std::array<unsigned char, 65536> buffer{}; DWORD read = 0; bool valid = true;
        for (;;) {
            if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) { valid = false; break; }
            if (!read) break;
            if (BCryptHashData(hash, buffer.data(), read, 0) < 0) { valid = false; break; }
        }
        std::array<unsigned char, 32> digest{};
        if (valid && BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0) {
            constexpr char digits[] = "0123456789abcdef";
            for (auto byte : digest) { result += digits[byte >> 4]; result += digits[byte & 15]; }
        }
    }
    if (hash) BCryptDestroyHash(hash);
    if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
    CloseHandle(file); return result;
}
std::string Utf8(const wchar_t* path) {
    const int count = WideCharToMultiByte(CP_UTF8, 0, path, -1, nullptr, 0, nullptr, nullptr);
    if (count <= 1) return {};
    std::string result(static_cast<size_t>(count), '\0');
    WideCharToMultiByte(CP_UTF8, 0, path, -1, result.data(), count, nullptr, nullptr);
    result.pop_back(); return result;
}
std::filesystem::path ClientConfigDirectory() {
    wchar_t filename[32768]{};
    const auto length = GetModuleFileNameW(nullptr, filename, 32768);
    if (!length || length >= 32768) throw std::runtime_error("Cannot locate the running client");
    const std::filesystem::path executable(filename);
    if (_wcsicmp(executable.filename().c_str(), L"gmod.exe") != 0)
        throw std::runtime_error("Multicore preferences are available only inside the game client");
    const auto cfg = executable.parent_path().parent_path().parent_path() / L"garrysmod" / L"cfg";
    if (!std::filesystem::is_directory(cfg)) throw std::runtime_error("Client cfg directory is missing");
    return cfg;
}
LUA_FUNCTION_STATIC(ReadMulticore) {
    gmodrp::MulticoreProfile profile;
    try { profile = gmodrp::ReadMulticoreProfile(ClientConfigDirectory()); }
    catch (const std::exception& error) { profile.error = error.what(); }
    LUA->CreateTable();
    LUA->PushBool(profile.enabled); LUA->SetField(-2, "enabled");
    LUA->PushBool(profile.managed); LUA->SetField(-2, "managed");
    LUA->PushString(profile.error.c_str()); LUA->SetField(-2, "error");
    LUA->CreateTable();
    for (size_t i = 0; i != profile.previous.size(); ++i) {
        LUA->PushNumber(static_cast<double>(i + 1)); LUA->PushString(profile.previous[i].c_str()); LUA->SetTable(-3);
    }
    LUA->SetField(-2, "previous"); return 1;
}
LUA_FUNCTION_STATIC(SaveMulticore) {
    const bool enabled = LUA->GetBool(1);
    std::array<std::string, 5> previous;
    for (int i = 0; i != 5; ++i) previous[static_cast<size_t>(i)] = LUA->CheckString(i + 2);
    try {
        const auto profile = gmodrp::SaveMulticoreProfile(ClientConfigDirectory(), enabled, previous);
        LUA->PushBool(profile.error.empty()); LUA->PushString(profile.error.c_str()); return 2;
    } catch (const std::exception& error) { LUA->PushBool(false); LUA->PushString(error.what()); return 2; }
}
LUA_FUNCTION_STATIC(Status) {
    static HMODULE observed = nullptr;
    static std::string path, digest;
    const auto module = GetModuleHandleW(L"d3d9.dll");
    if (module != observed) {
        observed = module; path.clear(); digest.clear();
        wchar_t filename[32768]{};
        if (module && GetModuleFileNameW(module, filename, 32768)) { path = Utf8(filename); digest = HashFile(filename); }
    }
    const bool dxvk = module && digest == "c126316f7478eaff1ad8087702eda5930f2400187b9c8b3592219c34f6632780";
    const bool vulkan = GetModuleHandleW(L"vulkan-1.dll") != nullptr;
    LUA->CreateTable();
    auto text = [&](const char* name, const std::string& value) { LUA->PushString(value.c_str()); LUA->SetField(-2, name); };
    auto flag = [&](const char* name, bool value) { LUA->PushBool(value); LUA->SetField(-2, name); };
    text("backend", dxvk ? (vulkan ? "Vulkan" : "DXVK loaded; Vulkan not initialized") : module ? "Direct3D 9 (unrecognized translator or native runtime)" : "Renderer not loaded");
    text("translator", dxvk ? "DXVK" : "Unknown / native");
    text("version", dxvk ? "3.1.1" : ""); text("path", path); text("sha256", digest);
    flag("loaded", module != nullptr); flag("verifiedDXVK", dxvk); flag("vulkanLoaded", vulkan);
    return 1;
}
}
GMOD_MODULE_OPEN() {
    menuAvailable = gmodrp::InstallMulticoreMenu(menuError);
    LUA->CreateTable(); LUA->PushCFunction(Status); LUA->SetField(-2, "status");
    LUA->PushCFunction(ReadMulticore); LUA->SetField(-2, "read_multicore_profile");
    LUA->PushCFunction(SaveMulticore); LUA->SetField(-2, "save_multicore_profile");
    LUA->PushCFunction(PollGraphicsMenu); LUA->SetField(-2, "poll_graphics_menu");
    LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL, "gmodrp_vulkan_info"); return 0;
}
GMOD_MODULE_CLOSE() { gmodrp::UninstallMulticoreMenu(); return 0; }
