/*
 * injector.c — Minimal WeChatFerry SDK loader
 *
 * Cross-compile with MinGW:
 *   x86_64-w64-mingw32-gcc -o injector.exe injector.c -lshlwapi
 *
 * Run under Wine:
 *   wine64 injector.exe [port]
 *
 * This loads sdk.dll and calls WxInitSDK(debug=false, port) which:
 *   1. Finds/starts WeChat.exe
 *   2. Injects spy.dll into WeChat's process
 *   3. Calls InitSpy to start the NNG RPC server
 */

#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

typedef int (__cdecl *WxInitSDK_t)(int debug, int port);
typedef int (__cdecl *WxDestroySDK_t)(void);

int main(int argc, char *argv[])
{
    int port = 10087;
    if (argc > 1) {
        port = atoi(argv[1]);
        if (port <= 0 || port > 65535) {
            fprintf(stderr, "Invalid port: %s\n", argv[1]);
            return 1;
        }
    }

    printf("[injector] Loading sdk.dll...\n");
    fflush(stdout);

    HMODULE hSdk = LoadLibraryA("sdk.dll");
    if (!hSdk) {
        fprintf(stderr, "[injector] Failed to load sdk.dll, error: %lu\n", GetLastError());
        return 1;
    }

    WxInitSDK_t WxInitSDK = (WxInitSDK_t)GetProcAddress(hSdk, "WxInitSDK");
    if (!WxInitSDK) {
        fprintf(stderr, "[injector] WxInitSDK export not found\n");
        FreeLibrary(hSdk);
        return 1;
    }

    printf("[injector] Calling WxInitSDK(debug=0, port=%d)...\n", port);
    printf("[injector] This will start WeChat and inject spy.dll\n");
    fflush(stdout);

    int ret = WxInitSDK(0, port);

    printf("[injector] WxInitSDK returned: %d\n", ret);
    fflush(stdout);

    if (ret != 0) {
        fprintf(stderr, "[injector] Injection failed (code %d)\n", ret);
        FreeLibrary(hSdk);
        return ret;
    }

    printf("[injector] Injection successful! NNG server on port %d (cmd) and %d (msg)\n",
           port, port + 1);
    printf("[injector] Keeping alive... (Ctrl+C to stop)\n");
    fflush(stdout);

    /* Keep process alive so sdk.dll stays loaded */
    while (1) {
        Sleep(60000);
    }

    return 0;
}
