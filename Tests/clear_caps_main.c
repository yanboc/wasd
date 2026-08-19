#include <stdio.h>

void clearCapsLockState(void);

int main(void) {
    clearCapsLockState();
    printf("已调用 IOHIDSetModifierLockState 强制关闭大写锁定\n");
    return 0;
}
