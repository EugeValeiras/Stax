#import "include/StaxPrivate.h"
#import <objc/runtime.h>

BOOL StaxVirtualDisplayAvailable(void) {
    return objc_getClass("CGVirtualDisplay") != NULL
        && objc_getClass("CGVirtualDisplayDescriptor") != NULL
        && objc_getClass("CGVirtualDisplaySettings") != NULL
        && objc_getClass("CGVirtualDisplayMode") != NULL;
}
