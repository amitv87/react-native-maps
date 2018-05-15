//
//  AIRGoogleMapManager.m
//  AirMaps
//
//  Created by Gil Birman on 9/1/16.
//


#import "AIRGoogleMapManager.h"
#import <React/RCTViewManager.h>
#import <React/RCTBridge.h>
#import <React/RCTUIManager.h>
#import <React/RCTConvert+CoreLocation.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTViewManager.h>
#import <React/RCTConvert.h>
#import <React/UIView+React.h>
#import "RCTConvert+GMSMapViewType.h"
#import "AIRGoogleMap.h"
#import "AIRMapMarker.h"
#import "AIRMapPolyline.h"
#import "AIRMapPolygon.h"
#import "AIRMapCircle.h"
#import "SMCalloutView.h"
#import "AIRGoogleMapMarker.h"
#import "RCTConvert+AirMap.h"
#import "AIRGoogleMapPolyline.h"

#import <MapKit/MapKit.h>
#import <QuartzCore/QuartzCore.h>

#define MAX_POLYLINE_LENGTH 100

static NSString *const RCTMapViewKey = @"MapView";


@interface AIRGoogleMapManager() <GMSMapViewDelegate>

@end

@interface Poly : NSObject

-(id)initWithColor:(UIColor *)color andWidth:(int)width andMap:(GMSMapView *)map;
-(void)newLine;
-(BOOL)checkMax:(BOOL) render;
-(void)addPoint:(AIRMapCoordinate *)coordinate;
-(void)addPoints:(NSArray<AIRMapCoordinate *> *)_coordinates;
-(void)removePoints:(int)count;
-(void)clear;

@end

@implementation AIRGoogleMapManager{
  NSMutableDictionary *polys;
}

RCT_EXPORT_MODULE()

- (UIView *)view
{
  AIRGoogleMap *map = [AIRGoogleMap new];
  map.delegate = self;
  return map;
}

RCT_EXPORT_VIEW_PROPERTY(initialRegion, MKCoordinateRegion)
RCT_EXPORT_VIEW_PROPERTY(region, MKCoordinateRegion)
RCT_EXPORT_VIEW_PROPERTY(showsBuildings, BOOL)
RCT_EXPORT_VIEW_PROPERTY(showsCompass, BOOL)
//RCT_EXPORT_VIEW_PROPERTY(showsScale, BOOL)  // Not supported by GoogleMaps
RCT_EXPORT_VIEW_PROPERTY(showsTraffic, BOOL)
RCT_EXPORT_VIEW_PROPERTY(zoomEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(rotateEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(scrollEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(pitchEnabled, BOOL)
RCT_EXPORT_VIEW_PROPERTY(showsUserLocation, BOOL)
RCT_EXPORT_VIEW_PROPERTY(showsMyLocationButton, BOOL)
RCT_EXPORT_VIEW_PROPERTY(customMapStyleString, NSString)
RCT_EXPORT_VIEW_PROPERTY(onMapReady, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onCameraMoveStarted, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onPress, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLongPress, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onChange, RCTBubblingEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onMarkerPress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onRegionChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onRegionChangeComplete, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(mapType, GMSMapViewType)
RCT_EXPORT_VIEW_PROPERTY(minZoomLevel, CGFloat)
RCT_EXPORT_VIEW_PROPERTY(maxZoomLevel, CGFloat)

RCT_EXPORT_METHOD(animateToRegion:(nonnull NSNumber *)reactTag
                  withRegion:(MKCoordinateRegion)region
                  withDuration:(CGFloat)duration)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRGoogleMap, got: %@", view);
    } else {
      // Core Animation must be used to control the animation's duration
      // See http://stackoverflow.com/a/15663039/171744
      [CATransaction begin];
      [CATransaction setAnimationDuration:duration/1000];
      AIRGoogleMap *mapView = (AIRGoogleMap *)view;
      GMSCameraPosition *camera = [AIRGoogleMap makeGMSCameraPositionFromMap:mapView andMKCoordinateRegion:region];
      [mapView animateToCameraPosition:camera];
      [CATransaction commit];
    }
  }];
}

RCT_EXPORT_METHOD(animateToCoordinate:(nonnull NSNumber *)reactTag
                  withRegion:(CLLocationCoordinate2D)latlng
                  withDuration:(CGFloat)duration)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRGoogleMap, got: %@", view);
    } else {
      [CATransaction begin];
      [CATransaction setAnimationDuration:duration/1000];
      [(AIRGoogleMap *)view animateToLocation:latlng];
      [CATransaction commit];
    }
  }];
}

RCT_EXPORT_METHOD(fitToElements:(nonnull NSNumber *)reactTag
                  animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRGoogleMap, got: %@", view);
    } else {
      AIRGoogleMap *mapView = (AIRGoogleMap *)view;

      CLLocationCoordinate2D myLocation = ((AIRGoogleMapMarker *)(mapView.markers.firstObject)).realMarker.position;
      GMSCoordinateBounds *bounds = [[GMSCoordinateBounds alloc] initWithCoordinate:myLocation coordinate:myLocation];

      for (AIRGoogleMapMarker *marker in mapView.markers)
        bounds = [bounds includingCoordinate:marker.realMarker.position];

      [mapView animateWithCameraUpdate:[GMSCameraUpdate fitBounds:bounds withPadding:55.0f]];
    }
  }];
}

RCT_EXPORT_METHOD(fitToSuppliedMarkers:(nonnull NSNumber *)reactTag
                  markers:(nonnull NSArray *)markers
                  animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRGoogleMap, got: %@", view);
    } else {
      AIRGoogleMap *mapView = (AIRGoogleMap *)view;

      NSPredicate *filterMarkers = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        AIRGoogleMapMarker *marker = (AIRGoogleMapMarker *)evaluatedObject;
        return [marker isKindOfClass:[AIRGoogleMapMarker class]] && [markers containsObject:marker.identifier];
      }];

      NSArray *filteredMarkers = [mapView.markers filteredArrayUsingPredicate:filterMarkers];

      CLLocationCoordinate2D myLocation = ((AIRGoogleMapMarker *)(filteredMarkers.firstObject)).realMarker.position;
      GMSCoordinateBounds *bounds = [[GMSCoordinateBounds alloc] initWithCoordinate:myLocation coordinate:myLocation];

      for (AIRGoogleMapMarker *marker in filteredMarkers)
        bounds = [bounds includingCoordinate:marker.realMarker.position];

      [mapView animateWithCameraUpdate:[GMSCameraUpdate fitBounds:bounds withPadding:55.0f]];
    }
  }];
}

RCT_EXPORT_METHOD(fitToCoordinates:(nonnull NSNumber *)reactTag
                  coordinates:(nonnull NSArray<AIRMapCoordinate *> *)coordinates
                  edgePadding:(nonnull NSDictionary *)edgePadding
                  animated:(BOOL)animated)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRGoogleMap, got: %@", view);
    } else {
      AIRGoogleMap *mapView = (AIRGoogleMap *)view;

      CLLocationCoordinate2D myLocation = coordinates.firstObject.coordinate;
      GMSCoordinateBounds *bounds = [[GMSCoordinateBounds alloc] initWithCoordinate:myLocation coordinate:myLocation];

      for (AIRMapCoordinate *coordinate in coordinates)
        bounds = [bounds includingCoordinate:coordinate.coordinate];

      // Set Map viewport
      CGFloat top = [RCTConvert CGFloat:edgePadding[@"top"]];
      CGFloat right = [RCTConvert CGFloat:edgePadding[@"right"]];
      CGFloat bottom = [RCTConvert CGFloat:edgePadding[@"bottom"]];
      CGFloat left = [RCTConvert CGFloat:edgePadding[@"left"]];

      [CATransaction begin];
      [CATransaction setAnimationDuration:1.5];
      [mapView animateWithCameraUpdate:[GMSCameraUpdate fitBounds:bounds withEdgeInsets:UIEdgeInsetsMake(top, left, bottom, right)]];
      [CATransaction commit];
    }
  }];
}

RCT_EXPORT_METHOD(takeSnapshot:(nonnull NSNumber *)reactTag
                  withWidth:(nonnull NSNumber *)width
                  withHeight:(nonnull NSNumber *)height
                  withRegion:(MKCoordinateRegion)region
                  withCallback:(RCTResponseSenderBlock)callback)
{
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      AIRGoogleMap *mapView = (AIRGoogleMap *)view;

      // TODO: currently we are ignoring width, height, region

      UIGraphicsBeginImageContextWithOptions(mapView.frame.size, YES, 0.0f);
      [mapView.layer renderInContext:UIGraphicsGetCurrentContext()];
      UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
      UIGraphicsEndImageContext();

      NSTimeInterval timeStamp = [[NSDate date] timeIntervalSince1970];
      NSString *pathComponent = [NSString stringWithFormat:@"Documents/snapshot-%.20lf.png", timeStamp];
      NSString *filePath = [NSHomeDirectory() stringByAppendingPathComponent: pathComponent];

      NSData *data = UIImagePNGRepresentation(image);
      [data writeToFile:filePath atomically:YES];
      NSDictionary *snapshotData = @{
                                     @"uri": filePath,
                                     @"data": [data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn]
                                     };
      callback(@[[NSNull null], snapshotData]);
    }
  }];
}

- (NSDictionary *)constantsToExport {
  return @{ @"legalNotice": [GMSServices openSourceLicenseInfo] };
}

- (void)mapViewDidFinishTileRendering:(GMSMapView *)mapView {
    AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
    [googleMapView didFinishTileRendering];
}

- (BOOL)mapView:(GMSMapView *)mapView didTapMarker:(GMSMarker *)marker {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  return [googleMapView didTapMarker:marker];
}

- (void)mapView:(GMSMapView *)mapView didTapOverlay:(GMSPolygon *)polygon {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  [googleMapView didTapPolygon:polygon];
}

- (void)mapView:(GMSMapView *)mapView didTapAtCoordinate:(CLLocationCoordinate2D)coordinate {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  [googleMapView didTapAtCoordinate:coordinate];
}

- (void)mapView:(GMSMapView *)mapView didLongPressAtCoordinate:(CLLocationCoordinate2D)coordinate {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  [googleMapView didLongPressAtCoordinate:coordinate];
}

- (void)mapView:(GMSMapView *)mapView didChangeCameraPosition:(GMSCameraPosition *)position {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  [googleMapView didChangeCameraPosition:position];
}

-(void)mapView:(GMSMapView *)mapView willMove:(BOOL)gesture{
    AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
    [googleMapView mapViewWillMove:gesture];
}

- (void)mapView:(GMSMapView *)mapView idleAtCameraPosition:(GMSCameraPosition *)position {
  AIRGoogleMap *googleMapView = (AIRGoogleMap *)mapView;
  [googleMapView idleAtCameraPosition:position];
}

- (UIView *)mapView:(GMSMapView *)mapView markerInfoWindow:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  return [aMarker.fakeMarker markerInfoWindow];}

- (UIView *)mapView:(GMSMapView *)mapView markerInfoContents:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  return [aMarker.fakeMarker markerInfoContents];
}

- (void)mapView:(GMSMapView *)mapView didTapInfoWindowOfMarker:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  [aMarker.fakeMarker didTapInfoWindowOfMarker:aMarker];
}

- (void)mapView:(GMSMapView *)mapView didBeginDraggingMarker:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  [aMarker.fakeMarker didBeginDraggingMarker:aMarker];
}

- (void)mapView:(GMSMapView *)mapView didEndDraggingMarker:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  [aMarker.fakeMarker didEndDraggingMarker:aMarker];
}

- (void)mapView:(GMSMapView *)mapView didDragMarker:(GMSMarker *)marker {
  AIRGMSMarker *aMarker = (AIRGMSMarker *)marker;
  [aMarker.fakeMarker didDragMarker:aMarker];
}

#pragma mark - Custom functions to support Ajjas App

RCT_EXPORT_METHOD(clearPoly:(nonnull NSNumber *)reactTag withKey:(NSString *)key){
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      Poly *poly = polys[key];
      if (poly != NULL)
        [poly clear];

      [polys removeObjectForKey:key];
    }
  }];
}

RCT_EXPORT_METHOD(createPoly:(nonnull NSNumber *)reactTag withKey:(NSString *)key withColor:(NSString *)color withWidth:(int)width){
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      NSLog(@"Reciev Color Here as :::: %@",color);
      UIColor *colr = [self colorFromHexString:color];
      if (polys == nil) {
        polys = [[NSMutableDictionary alloc] init];
      }
      if (polys[key] == NULL) {
        [polys setObject:[[Poly alloc] initWithColor:colr andWidth:width andMap:view] forKey:key];
      }
    }
  }];
}

RCT_EXPORT_METHOD(addPointToPoly:(nonnull NSNumber *)reactTag withKey:(NSString *)key withRegion:(AIRMapCoordinate *)latlng){
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      Poly *poly = polys[key];
      if (poly != NULL) {
        [poly addPoint:latlng];
      }
    }
  }];
}

RCT_EXPORT_METHOD(addPointsToPoly:(nonnull NSNumber *)reactTag withKey:(NSString *)key coordinates:(nonnull NSArray<AIRMapCoordinate *> *)coordinates){  
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      
      Poly *poly = polys[key];
      if (poly != NULL) {
        [poly addPoints:coordinates];
      }
    }
  }];
}

RCT_EXPORT_METHOD(removePointsFromPoly:(nonnull NSNumber *)reactTag withKey:(NSString *)key withCount:(int)count){
  [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    id view = viewRegistry[reactTag];
    if (![view isKindOfClass:[AIRGoogleMap class]]) {
      RCTLogError(@"Invalid view returned from registry, expecting AIRMap, got: %@", view);
    } else {
      Poly *poly = polys[key];
      if (poly != NULL) {
        [poly removePoints:count];
      }
    }
  }];
}

-(UIColor *)colorFromHexString:(NSString *)hexString {
  unsigned rgbValue = 0;
  NSScanner *scanner = [NSScanner scannerWithString:hexString];
  [scanner setScanLocation:1]; // bypass '#' character
  [scanner scanHexInt:&rgbValue];
  return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

@end

#pragma mark - Poly Class

@implementation Poly{
  NSMutableArray<GMSPolyline *> * polylines;
  NSMutableArray<GMSMutablePath *> * paths;
  UIColor *Color;
  int Width;
  GMSMapView *Map;
}

-(id)initWithColor:(UIColor *)color andWidth:(int)width andMap:(GMSMapView *)map{
  self = [super init];
  if (self) {
    polylines = [[NSMutableArray alloc] init];
    paths = [NSMutableArray new];
    Color = color;
    Width = width / 3;
    Map = map;
    
  }
  return self;
}

-(void)newLine{
  GMSMutablePath *path = [GMSMutablePath new];
  GMSPolyline *polyline = [GMSPolyline polylineWithPath:path];
  polyline.strokeWidth = Width;
  polyline.strokeColor = Color;
  polyline.map = Map;
  [polylines addObject:polyline];
  [paths addObject:path];
}

-(BOOL)checkMax:(BOOL) render{
  if(polylines.count > 0){
    GMSPolyline* polyline = polylines[polylines.count - 1];
    if (polyline.path.count >= MAX_POLYLINE_LENGTH){
      if (render){
        [polyline setPath:polyline.path];
      }
      [self newLine];
      return TRUE;
    }
  }
  return FALSE;
}

-(void)addPoint:(AIRMapCoordinate *)coordinate{
  [self checkMax:false];
  if (polylines.count == 0) [self newLine];
  GMSMutablePath *path = paths[paths.count - 1];
  [path addCoordinate:coordinate.coordinate];
  [polylines[polylines.count - 1] setPath:path];
}

-(void)addPoints:(NSArray<AIRMapCoordinate *> *)_coordinates{

  [self checkMax:false];
  if (polylines.count == 0) [self newLine];
  GMSMutablePath *path = paths[paths.count - 1];

  for (AIRMapCoordinate *coordinate in _coordinates) {
    [path addCoordinate:coordinate.coordinate];
    if([self checkMax:TRUE]){
      path = paths[paths.count - 1];
    }
  }

  if (path.count > 1) {
    [polylines[polylines.count - 1] setPath:path];
  }
}

-(void)removePoints:(int)count{
  int numRemovedPoints = 0;
  int numPolylines = (int)polylines.count - 1;

  for(int i = 0; i <= numPolylines; i++){
    int index = numPolylines - i;
    int numPointsToBeRemoved = count - numRemovedPoints;


    GMSPolyline *polyline = polylines[index];
    if(polylines.count <= numPointsToBeRemoved){
      numRemovedPoints += polylines.count;
      polyline = nil;
      polyline.path = nil;
      [polylines removeObjectAtIndex:index];
      [paths removeObjectAtIndex:index];
      // Log.d("removePoints full", "index: " + index + ", numRemovedPoints: " + numRemovedPoints);
    }
    else{
      NSRange range;
      range.location = 0;
      range.length = polylines.count -1 - numPointsToBeRemoved;

      polylines = [[polylines subarrayWithRange:range] mutableCopy];
      paths = [[paths subarrayWithRange:range] mutableCopy];
      numRemovedPoints += numPointsToBeRemoved;
      polylines[polylines.count - 1].path=paths[paths.count - 1];
      // Log.d("removePoints partial", "index: " + index + ", numRemovedPoints: " + numRemovedPoints);
    }
    if(numRemovedPoints == count)
      break;
  }
  
}
-(void)clear{
  for (GMSPolyline __strong *polyline in polylines) {
    polyline.map = nil;
    polyline = nil;
  }
  [polylines removeAllObjects];
  [paths removeAllObjects];
}

@end
