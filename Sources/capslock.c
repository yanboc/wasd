#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

// 物理 Caps Lock 键的按下会在 HID 驱动层直接锁定大写状态，
// 仅靠 CGEventTap 吞掉 flagsChanged 事件无法阻止，必须通过 IOKit 强制复位。
void clearCapsLockState(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!service) return;
    io_connect_t connect = IO_OBJECT_NULL;
    if (IOServiceOpen(service, mach_task_self_, kIOHIDParamConnectType, &connect) == KERN_SUCCESS) {
        IOHIDSetModifierLockState(connect, kIOHIDCapsLockState, false);
        IOServiceClose(connect);
    }
    IOObjectRelease(service);
}
