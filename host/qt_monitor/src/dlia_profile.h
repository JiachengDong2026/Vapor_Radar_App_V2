#pragma once
#include <QtGlobal>

// Both supported profiles use the strictly checked 1 MS/s AD4630 interface.
// The 12.5 MS/s legacy profiles are not compatible with that interface.
constexpr bool supportedDliaProfile(quint32 profile) {
    return profile == 0x00020101u || profile == 0x00040101u;
}
