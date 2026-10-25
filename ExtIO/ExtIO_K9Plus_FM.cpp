// HDSDR ExtIO backend for the Colorlight K9+ 6 MS/s UDP IQ stream.
// ExtIO type 3: signed 16-bit interleaved I/Q, little-endian, Win32.
// SPDX-License-Identifier: MIT
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <atomic>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <thread>

#pragma comment(lib, "Ws2_32.lib")

using ExtCallback = void (*)(int, int, float, void *);

namespace {
constexpr int kIqPort = 50003;
constexpr int kControlPort = 50001;
constexpr int kHeaderBytes = 32;
constexpr int kPayloadBytes = 1440;
constexpr int kSamplesPerPacket = kPayloadBytes / 2;
// HDSDR's spectrum pipeline is most reliable with a power-of-two callback
// block. 4096 also keeps the callback rate modest at 6 MS/s.
constexpr int kCallbackSamples = 4096;
constexpr long kSampleRate = 6000000;
constexpr double kRfSampleRate = 240000000.0;
constexpr long kDefaultCenterHz = 95000000;
constexpr long kMaximumCenterHz = 120000000;

std::atomic<ExtCallback> g_callback{nullptr};
std::atomic<bool> g_running{false};
std::atomic<long> g_center_hz{kDefaultCenterHz};
SOCKET g_rx = INVALID_SOCKET;
SOCKET g_control = INVALID_SOCKET;
sockaddr_in g_control_address{};
bool g_wsa_active = false;
std::thread g_worker;

uint32_t get_u32(const unsigned char *p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) |
           (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

uint64_t get_u64(const unsigned char *p) {
    uint64_t value = 0;
    for (int index = 0; index < 8; ++index)
        value |= uint64_t(p[index]) << (8 * index);
    return value;
}

void put_u32(unsigned char *p, uint32_t value) {
    for (int index = 0; index < 4; ++index)
        p[index] = static_cast<unsigned char>(value >> (8 * index));
}

void send_tune(long frequency_hz) {
    if (g_control == INVALID_SOCKET || frequency_hz < 0)
        return;
    unsigned char message[12] = {'K', '9', 'T', 'U'};
    put_u32(message + 4, static_cast<uint32_t>(frequency_hz));
    const auto phase_increment = static_cast<uint32_t>(std::llround(
        double(frequency_hz) * 4294967296.0 / kRfSampleRate));
    put_u32(message + 8, phase_increment);
    for (int attempt = 0; attempt < 4; ++attempt) {
        sendto(g_control, reinterpret_cast<const char *>(message), sizeof(message), 0,
               reinterpret_cast<const sockaddr *>(&g_control_address),
               sizeof(g_control_address));
        Sleep(10);
    }
}

void deliver(std::array<int16_t, kCallbackSamples * 2> &output, int &fill) {
    if (fill != kCallbackSamples)
        return;
    auto callback = g_callback.load();
    if (callback)
        callback(kCallbackSamples, 0, 0.0f, output.data());
    fill = 0;
}

void capture_loop() {
    std::array<unsigned char, 2048> datagram{};
    std::array<int16_t, kCallbackSamples * 2> output{};
    uint64_t expected_sample = 0;
    bool have_expected = false;
    bool have_dc = false;
    float dc_i = 0.0f;
    float dc_q = 0.0f;
    constexpr float kDcAlpha = 1.0f / 65536.0f;
    int fill = 0;

    while (g_running.load()) {
        sockaddr_in peer{};
        int peer_length = sizeof(peer);
        const int received = recvfrom(
            g_rx, reinterpret_cast<char *>(datagram.data()),
            static_cast<int>(datagram.size()), 0,
            reinterpret_cast<sockaddr *>(&peer), &peer_length);
        if (received < 0) {
            if (!g_running.load())
                break;
            const int error = WSAGetLastError();
            if (error == WSAETIMEDOUT || error == WSAEWOULDBLOCK || error == WSAEINTR)
                continue;
            continue;
        }

        const unsigned char *packet = datagram.data();
        if (received != kHeaderBytes + kPayloadBytes ||
            std::memcmp(packet, "K9IQ", 4) != 0 || packet[4] != 2 ||
            (packet[5] & 0x02) == 0 || packet[6] != kHeaderBytes || packet[7] != 0 ||
            get_u32(packet + 16) != static_cast<uint32_t>(kSampleRate))
            continue;

        const uint64_t first_sample = get_u64(packet + 20);
        if (!have_expected || first_sample < expected_sample ||
            first_sample > expected_sample + uint64_t(8 * kSamplesPerPacket)) {
            // Startup, retune, or a large discontinuity: start a fresh HDSDR block.
            fill = 0;
            expected_sample = first_sample;
            have_expected = true;
        }

        if (!have_dc) {
            float sum_i = 0.0f;
            float sum_q = 0.0f;
            for (int sample = 0; sample < kSamplesPerPacket; ++sample) {
                sum_i += static_cast<int8_t>(packet[kHeaderBytes + 2 * sample]);
                sum_q += static_cast<int8_t>(packet[kHeaderBytes + 2 * sample + 1]);
            }
            dc_i = sum_i / kSamplesPerPacket;
            dc_q = sum_q / kSamplesPerPacket;
            have_dc = true;
        }

        // Preserve the complex-sample timeline across a small UDP loss.
        while (expected_sample < first_sample) {
            output[2 * fill] = 0;
            output[2 * fill + 1] = 0;
            ++fill;
            ++expected_sample;
            deliver(output, fill);
        }

        for (int sample = 0; sample < kSamplesPerPacket; ++sample) {
            const int offset = kHeaderBytes + 2 * sample;
            const auto i8 = static_cast<int8_t>(packet[offset]);
            const auto q8 = static_cast<int8_t>(packet[offset + 1]);
            dc_i += kDcAlpha * (float(i8) - dc_i);
            dc_q += kDcAlpha * (float(q8) - dc_q);
            const long corrected_i = std::lround((float(i8) - dc_i) * 256.0f);
            const long corrected_q = std::lround((float(q8) - dc_q) * 256.0f);
            output[2 * fill] = static_cast<int16_t>(
                corrected_i < -32768 ? -32768 : corrected_i > 32767 ? 32767 : corrected_i);
            output[2 * fill + 1] = static_cast<int16_t>(
                corrected_q < -32768 ? -32768 : corrected_q > 32767 ? 32767 : corrected_q);
            ++fill;
            ++expected_sample;
            deliver(output, fill);
        }
    }
}

void close_network() {
    if (g_rx != INVALID_SOCKET) {
        closesocket(g_rx);
        g_rx = INVALID_SOCKET;
    }
    if (g_control != INVALID_SOCKET) {
        closesocket(g_control);
        g_control = INVALID_SOCKET;
    }
    if (g_wsa_active) {
        WSACleanup();
        g_wsa_active = false;
    }
}
} // namespace

extern "C" {
__declspec(dllexport) bool __stdcall InitHW(char *name, char *model, int &type) {
    strncpy_s(name, 16, "K9+ FM 6M", _TRUNCATE);
    strncpy_s(model, 16, "UDP IQ8", _TRUNCATE);
    type = 3; // exthwUSBdata16
    return true;
}

__declspec(dllexport) bool __stdcall OpenHW() {
    if (g_wsa_active)
        return true;
    WSADATA winsock{};
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0)
        return false;
    g_wsa_active = true;
    g_rx = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    g_control = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (g_rx == INVALID_SOCKET || g_control == INVALID_SOCKET) {
        close_network();
        return false;
    }

    BOOL enabled = TRUE;
    setsockopt(g_rx, SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char *>(&enabled), sizeof(enabled));
    setsockopt(g_control, SOL_SOCKET, SO_BROADCAST,
               reinterpret_cast<const char *>(&enabled), sizeof(enabled));
    int receive_bytes = 32 * 1024 * 1024;
    setsockopt(g_rx, SOL_SOCKET, SO_RCVBUF,
               reinterpret_cast<const char *>(&receive_bytes), sizeof(receive_bytes));
    DWORD timeout_ms = 200;
    setsockopt(g_rx, SOL_SOCKET, SO_RCVTIMEO,
               reinterpret_cast<const char *>(&timeout_ms), sizeof(timeout_ms));

    sockaddr_in listen_address{};
    listen_address.sin_family = AF_INET;
    listen_address.sin_addr.s_addr = htonl(INADDR_ANY);
    listen_address.sin_port = htons(kIqPort);
    if (bind(g_rx, reinterpret_cast<const sockaddr *>(&listen_address),
             sizeof(listen_address)) != 0) {
        close_network();
        return false;
    }

    g_control_address.sin_family = AF_INET;
    g_control_address.sin_port = htons(kControlPort);
    char *configured_host = nullptr;
    size_t configured_length = 0;
    _dupenv_s(&configured_host, &configured_length, "K9PLUS_CONTROL_HOST");
    const char *host = configured_host && *configured_host
        ? configured_host : "192.168.10.255";
    const int valid_address = inet_pton(AF_INET, host, &g_control_address.sin_addr);
    std::free(configured_host);
    if (valid_address != 1) {
        close_network();
        return false;
    }
    return true;
}

__declspec(dllexport) int __stdcall StartHW(long frequency_hz) {
    if (!g_wsa_active || g_rx == INVALID_SOCKET)
        return 0;
    if (frequency_hz >= 0 && frequency_hz <= kMaximumCenterHz)
        g_center_hz.store(frequency_hz);
    send_tune(g_center_hz.load());
    if (!g_running.exchange(true))
        g_worker = std::thread(capture_loop);
    return kCallbackSamples;
}

__declspec(dllexport) void __stdcall StopHW() {
    if (g_running.exchange(false) && g_worker.joinable())
        g_worker.join();
}

__declspec(dllexport) void __stdcall CloseHW() {
    StopHW();
    close_network();
}

__declspec(dllexport) int __stdcall SetHWLO(long frequency_hz) {
    if (frequency_hz < 0 || frequency_hz > kMaximumCenterHz)
        return 1;
    g_center_hz.store(frequency_hz);
    send_tune(frequency_hz);
    return 0;
}

__declspec(dllexport) long __stdcall GetHWLO() { return g_center_hz.load(); }
__declspec(dllexport) long __stdcall GetHWSR() { return kSampleRate; }
__declspec(dllexport) long __stdcall GetTune() { return g_center_hz.load(); }
__declspec(dllexport) int __stdcall GetStatus() { return 0; }
__declspec(dllexport) void __stdcall TuneChanged(long) {}
__declspec(dllexport) void __stdcall GetFilters(int &low, int &high, int &pitch) {
    low = -2700000;
    high = 2700000;
    pitch = 0;
}
__declspec(dllexport) void __stdcall SetCallback(ExtCallback callback) {
    g_callback.store(callback);
    if (callback)
        callback(-1, 101, 0.0f, nullptr);
}
__declspec(dllexport) int __stdcall ExtIoGetSrates(int index, double *rate) {
    if (index != 0 || !rate)
        return 1;
    *rate = double(kSampleRate);
    return 0;
}
__declspec(dllexport) int __stdcall ExtIoGetActualSrateIdx() { return 0; }
__declspec(dllexport) int __stdcall ExtIoSetSrate(int index) { return index == 0 ? 0 : 1; }
__declspec(dllexport) long __stdcall ExtIoGetBandwidth(int index) {
    return index == 0 ? 5400000 : 0;
}
__declspec(dllexport) void __stdcall ShowGUI() {}
__declspec(dllexport) void __stdcall HideGUI() {}
__declspec(dllexport) void __stdcall SwitchGUI() {}
} // extern "C"

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(instance);
    return TRUE;
}
