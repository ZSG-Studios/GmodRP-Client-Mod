#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "multicore_profile.hpp"
#include <fstream>
#include <iostream>

namespace {
int assertions = 0;
void Check(bool condition, const char* message) {
    ++assertions; if (!condition) throw std::runtime_error(message);
}
void Put(const std::filesystem::path& path, const std::string& value) { std::ofstream file(path, std::ios::binary); file << value; }
std::string Get(const std::filesystem::path& path) { bool exists = false; return gmodrp::multicore_detail::Read(path, 1024 * 1024, exists); }
}
int main() {
    try {
        const auto root = std::filesystem::path(__FILE__).parent_path() / "build" / (L"multicore-test" + gmodrp::multicore_detail::UniqueSuffix());
        std::filesystem::create_directories(root);
        const std::array<std::string, 5> originals{"0", "-1", "0", "0.5", "1e0"};
        const std::string original = "// external config\r\nbind F1 help\nno_final_newline";
        Put(root / "autoexec.cfg", original);
        auto result = gmodrp::SaveMulticoreProfile(root, true, originals);
        Check(result.error.empty() && result.enabled && result.managed, "Enable failed");
        Check(result.previous == originals, "Original values lost");
        Check(Get(root / "autoexec.cfg") == gmodrp::multicore_detail::Block("\r\n") + original, "Unrelated bytes changed on enable");
        const auto before = Get(root / "autoexec.cfg");
        result = gmodrp::SaveMulticoreProfile(root, true, {"1", "2", "1", "1", "1"});
        Check(result.error.empty() && result.previous == originals && Get(root / "autoexec.cfg") == before, "Reenable overwrote originals");
        Put(root / "autoexec.cfg", "// added externally\n" + before + "\nnew_cvar 9\r\n");
        result = gmodrp::SaveMulticoreProfile(root, false, originals);
        Check(result.error.empty() && !result.enabled && !result.managed, "Disable failed");
        Check(Get(root / "autoexec.cfg") == "// added externally\n" + original + "\nnew_cvar 9\r\n", "Disable discarded external edits");
        Check(gmodrp::ReadMulticoreProfile(root).previous == originals, "Disabled state lost originals");
        size_t backups = 0; for (const auto& entry : std::filesystem::directory_iterator(root)) if (entry.path().extension() == L".bak") ++backups;
        Check(backups >= 3, "Recoverable backups missing");
        auto badCase = [&](const std::string& text, const char* message) {
            Put(root / "autoexec.cfg", text);
            const auto state = Get(root / "gmodrp-multicore-profile.txt");
            const auto saved = gmodrp::SaveMulticoreProfile(root, true, originals);
            std::ifstream input(root / "autoexec.cfg", std::ios::binary);
            const std::string after((std::istreambuf_iterator<char>(input)), {});
            Check(!saved.error.empty() && after == text && Get(root / "gmodrp-multicore-profile.txt") == state, message);
        };
        badCase("// GmodRP multicore BEGIN\n", "Orphan marker changed file");
        badCase(gmodrp::multicore_detail::Block("\n") + gmodrp::multicore_detail::Block("\n"), "Duplicate block changed file");
        badCase("// GmodRP multicore BEGIN\ncustom 1\n// GmodRP multicore END\n", "Edited block changed file");
        badCase(std::string("abc\0def", 7), "NUL file changed");
        badCase(std::string(1024 * 1024 + 1, 'x'), "Oversize file changed");
        Put(root / "autoexec.cfg", original);
        const auto state = Get(root / "gmodrp-multicore-profile.txt");
        result = gmodrp::SaveMulticoreProfile(root, true, {"0", "2;quit", "0", "0", "0"});
        Check(!result.error.empty() && Get(root / "autoexec.cfg") == original && Get(root / "gmodrp-multicore-profile.txt") == state, "Invalid numeric changed file");
        Put(root / "gmodrp-multicore-profile.txt", "GMODRP_MULTICORE_V1\n0\n0\n0\n0\n0\nNaN\n");
        Check(!gmodrp::ReadMulticoreProfile(root).error.empty(), "Invalid saved numeric accepted");
        const auto optional = root / "optional"; std::filesystem::create_directory(optional);
        Put(optional / "autoexec.cfg", original);
        const std::array<std::string, 5> unavailable{"0", "-1", "0", "unavailable", "unavailable"};
        result = gmodrp::SaveMulticoreProfile(optional, true, unavailable);
        Check(result.error.empty() && result.previous == unavailable, "Unavailable optional cvars rejected");
        const auto optionalCfg = Get(optional / "autoexec.cfg");
        Check(optionalCfg == "// GmodRP multicore BEGIN\r\ngmod_mcore_test 1\r\nmat_queue_mode 2\r\ncl_threaded_bone_setup 1\r\n// GmodRP multicore END\r\n" + original,
            "Unavailable cvars emitted or required commands missing");
        result = gmodrp::ReadMulticoreProfile(optional);
        Check(result.error.empty() && result.enabled && result.previous == unavailable, "Unavailable state did not round trip");
        result = gmodrp::SaveMulticoreProfile(optional, true, originals);
        Check(result.error.empty() && result.previous == unavailable && Get(optional / "autoexec.cfg") == optionalCfg,
            "Reenable replaced unavailable original state");
        result = gmodrp::SaveMulticoreProfile(optional, false, originals);
        Check(result.error.empty() && result.previous == unavailable && Get(optional / "autoexec.cfg") == original,
            "Unavailable disable failed to restore external bytes");
        for (size_t i = 0; i < 3; ++i) {
            auto invalid = originals; invalid[i] = "unavailable";
            const auto originalState = Get(optional / "gmodrp-multicore-profile.txt");
            result = gmodrp::SaveMulticoreProfile(optional, true, invalid);
            Check(!result.error.empty() && Get(optional / "autoexec.cfg") == original
                && Get(optional / "gmodrp-multicore-profile.txt") == originalState, "Required cvar accepted unavailable sentinel");
        }
        Put(optional / "gmodrp-multicore-profile.txt", "GMODRP_MULTICORE_V1\n0\nunavailable\n0\n0\n0\n0\n");
        Check(!gmodrp::ReadMulticoreProfile(optional).error.empty(), "Saved required cvar accepted unavailable sentinel");
        std::cout << assertions << " multicore assertions passed; fixtures retained at " << root.string() << '\n';
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
