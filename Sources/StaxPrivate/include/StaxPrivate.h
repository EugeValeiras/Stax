//
//  Declaraciones de la API privada de pantallas virtuales de CoreGraphics.
//
//  Son las clases que usan DeskPad y BetterDisplay para registrar un monitor que no existe.
//  Apple no las documenta ni las expone en ningún header público, así que las declaramos acá;
//  las implementaciones vienen de CoreGraphics.framework, contra el que ya linkeamos.
//
//  Verificado en macOS 26.5.1. Si una versión futura las saca, `CGVirtualDisplayAvailable()`
//  devuelve false y Stax sigue funcionando con la ventana espejo de siempre.
//

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
/// 1 = la pantalla es Retina: el modo declara los puntos y el respaldo va al doble de píxeles.
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic) unsigned int rotation;
- (instancetype)init;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(copy, nonatomic) void (^terminationHandler)(id _Nullable, id _Nullable);
- (instancetype)init;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

/// ¿Están las cuatro clases en este macOS? Se consulta antes de intentar crear nada.
BOOL StaxVirtualDisplayAvailable(void);

NS_ASSUME_NONNULL_END
