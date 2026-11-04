#pragma once
#include <windows.h>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

namespace gmodrp {
struct MulticoreProfile {
    bool enabled = false, managed = false;
    std::array<std::string, 5> previous{};
    std::string error;
};
namespace multicore_detail {
inline constexpr std::string_view begin = "// GmodRP multicore BEGIN";
inline constexpr std::string_view end = "// GmodRP multicore END";
inline constexpr const char* commands[] = {"gmod_mcore_test 1", "mat_queue_mode 2",
    "cl_threaded_bone_setup 1", "r_threaded_client_shadow_manager 1", "r_threaded_renderables 1"};
inline std::string Block(std::string_view newline, const std::array<std::string, 5>* previous = nullptr) {
    std::string out(begin); out += newline;
    for (size_t i = 0; i < 5; ++i) {
        if (i >= 3 && previous && (*previous)[i] == "unavailable") continue;
        out += commands[i]; out += newline;
    }
    out += end; out += newline; return out;
}
inline bool Numeric(const std::string& value) {
    if (value.empty() || value.size() > 64) return false;
    for (const char c : value) if (!((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.' || c == 'e' || c == 'E')) return false;
    char* last = nullptr; const double number = std::strtod(value.c_str(), &last);
    return last == value.c_str() + value.size() && std::isfinite(number);
}
inline bool PreviousValid(size_t index, const std::string& value) {
    return Numeric(value) || (index >= 3 && index < 5 && value == "unavailable");
}
inline std::string Read(const std::filesystem::path& path, size_t limit, bool& exists) {
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        if (GetLastError() == ERROR_FILE_NOT_FOUND) { exists = false; return {}; }
        throw std::runtime_error("Cannot open multicore profile file");
    }
    exists = true; LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 || static_cast<unsigned long long>(size.QuadPart) > limit) {
        CloseHandle(file); throw std::runtime_error("Multicore profile file exceeds size limit");
    }
    std::string out(static_cast<size_t>(size.QuadPart), '\0'); DWORD count = 0;
    const bool okay = out.empty() || (ReadFile(file, out.data(), static_cast<DWORD>(out.size()), &count, nullptr) && count == out.size());
    CloseHandle(file);
    if (!okay || out.find('\0') != std::string::npos) throw std::runtime_error("Multicore profile file is unreadable or contains NUL");
    return out;
}
inline std::string Strip(std::string cfg, bool& managed, const std::array<std::string, 5>* previous = nullptr) {
    const auto first = cfg.find(begin), last = cfg.find(end); managed = first != std::string::npos;
    if (!managed && last == std::string::npos) return cfg;
    if (!managed || last == std::string::npos || first >= last || cfg.find(begin, first + 1) != std::string::npos
        || cfg.find(end, last + 1) != std::string::npos || (first && cfg[first - 1] != '\n'))
        throw std::runtime_error("Malformed or duplicate multicore markers; preserving autoexec");
    for (const auto newline : {std::string_view("\r\n"), std::string_view("\n")}) {
        const auto expected = Block(newline, previous);
        if (cfg.compare(first, expected.size(), expected) == 0) { cfg.erase(first, expected.size()); return cfg; }
    }
    throw std::runtime_error("Managed multicore block was edited; preserving autoexec");
}
inline MulticoreProfile Parse(const std::string& state) {
    MulticoreProfile out; size_t cursor = 0;
    auto line = [&]() {
        const auto endLine = state.find('\n', cursor);
        if (endLine == std::string::npos) throw std::runtime_error("Malformed multicore state");
        auto value = state.substr(cursor, endLine - cursor); cursor = endLine + 1; return value;
    };
    if (line() != "GMODRP_MULTICORE_V1") throw std::runtime_error("Unknown multicore state format");
    const auto enabled = line();
    if (enabled != "0" && enabled != "1") throw std::runtime_error("Invalid multicore state flag");
    out.enabled = enabled == "1";
    for (size_t i = 0; i < 5; ++i) {
        out.previous[i] = line();
        if (!PreviousValid(i, out.previous[i])) throw std::runtime_error("Invalid multicore original value or unsupported unavailable sentinel");
    }
    if (cursor != state.size()) throw std::runtime_error("Unexpected multicore state data");
    return out;
}
inline std::wstring UniqueSuffix() {
    static std::atomic<unsigned long> sequence{0}; FILETIME now{}; GetSystemTimeAsFileTime(&now);
    ULARGE_INTEGER tick{}; tick.LowPart = now.dwLowDateTime; tick.HighPart = now.dwHighDateTime;
    return L"." + std::to_wstring(tick.QuadPart) + L"." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(++sequence);
}
inline void AtomicWrite(const std::filesystem::path& path, const std::string& text, bool existed, const std::string& original) {
    bool currentExists = false; const auto current = Read(path, 1024 * 1024, currentExists);
    if (currentExists != existed || current != original) throw std::runtime_error("Profile file changed during save; preserving external edits");
    const auto suffix = UniqueSuffix();
    if (existed && !CopyFileW(path.c_str(), (path.wstring() + suffix + L".bak").c_str(), TRUE))
        throw std::runtime_error("Cannot back up multicore file; no replacement performed");
    const auto temporary = path.wstring() + suffix + L".tmp";
    HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot create multicore temporary file");
    DWORD count = 0;
    const bool okay = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &count, nullptr)
        && count == text.size() && FlushFileBuffers(file);
    CloseHandle(file);
    if (!okay || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Atomic multicore replacement failed; backup and temporary file preserved");
}
}
inline MulticoreProfile ReadMulticoreProfile(const std::filesystem::path& cfgDirectory) {
    MulticoreProfile out;
    try {
        bool cfgExists = false, stateExists = false;
        const auto cfg = multicore_detail::Read(cfgDirectory / L"autoexec.cfg", 1024 * 1024, cfgExists);
        const auto state = multicore_detail::Read(cfgDirectory / L"gmodrp-multicore-profile.txt", 4096, stateExists);
        if (stateExists) out = multicore_detail::Parse(state);
        bool managed = false; multicore_detail::Strip(cfg, managed, stateExists ? &out.previous : nullptr);
        out.managed = managed;
        if (out.enabled != managed) throw std::runtime_error("Multicore state and autoexec disagree; restore the saved backup before retrying");
    } catch (const std::exception& e) { out.error = e.what(); }
    return out;
}
inline MulticoreProfile SaveMulticoreProfile(const std::filesystem::path& cfgDirectory, bool enabled,
    const std::array<std::string, 5>& previous) {
    auto out = ReadMulticoreProfile(cfgDirectory);
    if (!out.error.empty()) return out;
    try {
        bool cfgExists = false, stateExists = false;
        const auto cfgPath = cfgDirectory / L"autoexec.cfg", statePath = cfgDirectory / L"gmodrp-multicore-profile.txt";
        const auto cfg = multicore_detail::Read(cfgPath, 1024 * 1024, cfgExists);
        const auto priorState = multicore_detail::Read(statePath, 4096, stateExists);
        if (stateExists) out = multicore_detail::Parse(priorState);
        bool managed = false; auto desired = multicore_detail::Strip(cfg, managed, stateExists ? &out.previous : nullptr);
        if (stateExists) {
            if (out.enabled != managed) throw std::runtime_error("Multicore state changed during save");
        }
        if (!enabled && !stateExists && !managed) return out;
        if (enabled && !out.enabled) out.previous = previous;
        for (size_t i = 0; i < 5; ++i)
            if (!multicore_detail::PreviousValid(i, out.previous[i])) throw std::runtime_error("Invalid multicore original value or unsupported unavailable sentinel");
        if (enabled) desired.insert(0, multicore_detail::Block("\r\n", &out.previous));
        std::string state = "GMODRP_MULTICORE_V1\n"; state += enabled ? "1\n" : "0\n";
        for (const auto& value : out.previous) { state += value; state += '\n'; }
        // Both files have recoverable backups and individually atomic replaces.
        // A failure between them is reported, and Read refuses inconsistent state.
        if (desired != cfg) multicore_detail::AtomicWrite(cfgPath, desired, cfgExists, cfg);
        if (state != priorState) multicore_detail::AtomicWrite(statePath, state, stateExists, priorState);
        out.enabled = enabled; out.managed = enabled;
    } catch (const std::exception& e) { out.error = e.what(); }
    return out;
}
}
