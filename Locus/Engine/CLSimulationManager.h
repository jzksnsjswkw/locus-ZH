//
//  CLSimulationManager.h
//  Locus
//
//  Private header for Apple's CLSimulationManager (CoreLocation).
//  This is the same private API used by Geranium / Andromeda / TrollTools /
//  udevs' locsim to inject simulated coordinates into locationd system-wide.
//  It works on stock iOS when the app carries the com.apple.locationd.simulation
//  entitlement and is installed via TrollStore (which preserves arbitrary
//  entitlements during re-signing).
//

#ifndef CLSimulationManager_h
#define CLSimulationManager_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CLSimulationManager : NSObject

@property (assign, nonatomic) uint8_t locationDeliveryBehavior;   // 0 = pass through, 1 = consider other factors
@property (assign, nonatomic) double locationDistance;
@property (assign, nonatomic) double locationInterval;
@property (assign, nonatomic) double locationSpeed;
@property (assign, nonatomic) uint8_t locationRepeatBehavior;     // 0 = unavailable, 1 = last entry, 2 = loop

- (void)clearSimulatedLocations;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;
- (void)appendSimulatedLocation:(id)arg1;
- (void)flush;
- (void)loadScenarioFromURL:(id)arg1;
- (void)setSimulatedWifiPower:(BOOL)arg1;
- (void)startWifiSimulation;
- (void)stopWifiSimulation;
- (void)setSimulatedCell:(id)arg1;
- (void)startCellSimulation;
- (void)stopCellSimulation;

@end

NS_ASSUME_NONNULL_END

#endif /* CLSimulationManager_h */