#pragma once
// Minimal ABI adapter for the SHA-256 pinned Windows x64 GameUI build.
// Offsets verified against that image and tested in its real native options UI.
// No SDK control-class layout or C++ object construction crosses the DLL boundary.
#include <cstdint>
#include <cstddef>
namespace renderer::native {
template<class R, class... A> R Call(void* object, size_t offset, A... args) {
    return reinterpret_cast<R(*)(void*, A...)>((*static_cast<void***>(object))[offset / sizeof(void*)])(object, args...);
}
using PanelHandle = uintptr_t;
static_assert(sizeof(PanelHandle) == 8);
struct EngineVGui {
    PanelHandle GetPanel(int kind) { return Call<PanelHandle>(this, 0x8, kind); }
};
struct Panels {
    // VPanelWrapper GetPos0x18->RVA1c5c0->VPanel1b750; GetSize0x28
    // ->RVA1c600->VPanel1b780, verified in the pinned vgui2 image.
    void GetPos(PanelHandle p, int& x, int& y) { Call<void>(this, 0x18, p, &x, &y); }
    void GetSize(PanelHandle p, int& w, int& h) { Call<void>(this, 0x28, p, &w, &h); }
    bool IsVisible(PanelHandle p) { return Call<bool>(this, 0x78, p); }
    int GetChildCount(PanelHandle p) { return Call<int>(this, 0x88, p); }
    PanelHandle GetChild(PanelHandle p, int n) { return Call<PanelHandle>(this, 0x90, p, n); }
    PanelHandle GetParent(PanelHandle p) { return Call<PanelHandle>(this, 0xa0, p); }
    bool IsFullyVisible(PanelHandle p) { return Call<bool>(this, 0xd0, p); }
    const char* GetName(PanelHandle p) { return Call<const char*>(this, 0x120, p); }
    const char* GetClassName(PanelHandle p) { return Call<const char*>(this, 0x128, p); }
    void* GetPanel(PanelHandle p, const char* module) { return Call<void*>(this, 0x1b8, p, module); }
};
}
