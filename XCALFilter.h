//
//  XCALFilter.h
//  XCAL
//
//  Copyright (c) 2012 autocalculate. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OsiriXAPI/PluginFilter.h>



@interface XCALFilter : PluginFilter 
{
  NSXMLElement *XMLroot;
  NSXMLDocument *xmlDoc;
  
  NSXMLElement *XML_Dicom_metadata;
  NSXMLElement *XML_calculations;
  NSXMLElement *XML_volume;
  
  NSArray     *PixList;
  DCMPix        *curPix;
  
  NSString* XML_OutFilename;
  NSString* XCAL_Directory;
  char  param_fname[256];
  char *homeDir;
  
  float threshold;
  
  float ROI_size_xy_mm;
  float ROI_size_z_mm;
  
  int num_z;	//in pixels
  int num_x;
  int num_y;
  double spaceZ;	//width of slices in mm

  float centroid_x;	//in pixels
  float centroid_y;
  float centroid_z;
  
  float cyl_radius;// = 22.5;//30;	//bfe 10.29.12
  float cyl_length;// = 45;//60;
  float cyl_volume;
  float segmented_volume;
  
  float X_Center;
  float Y_Center;
  float Z_Center;
  bool b_absoluteposition;
  
  BOOL b_FlippedSeries;
  BOOL show_center_pixel;
  BOOL b_SUVMode;	  //else is pixel value mode

}

- (long) filterImage:(NSString*) menuName;

//- (void) AddtoXMLdoc:(NSString*) metakey: (NSXMLElement *) parent;
- (void) AddtoXMLdoc:(NSString*) metakey: (NSXMLElement *)XMLparent;
- (void) AddtoXMLdocRoot:(NSString*) metakey;
- (void) AddGenerictoXMLdoc:(NSString*) key: (NSString*) value: (NSXMLElement *)XMLparent;
- (void) AddtoXMLdocDICOM:(NSString*) metakey;
- (void) AddtoXMLdoc_calculation:(NSString*) key: (NSString*) value;
- (void) AddtoXMLdoc_volume:(NSString*) key: (NSString*) value;
- (void) Add_DICOM_XML_Attributes;

- (BOOL) PopulateCommandLineItemFromFile:(char *) key: (char *) value;
- (BOOL)  ReadCommandParameterFile:(char *) filename;
- (void) RemoveTrailingSpaces:(char *) value;
- (void) GenerateFolder:(char *) OutputFolderName;
- (void) AddtoXML_Nesteditem_DICOM:(NSString*) metakeyGE:(NSString*) metakey: (NSString*) parentmetakey:(NSXMLElement *)XMLparent;

- (BOOL) FindCentroid;
-(void) FreeObject: (void * )object;
-(void) VerifyAllocation: (void * )object;
- (NSString*) GetDICOMAttribute:(NSString*) metakey;
//- (void) FindCentroid:(float) x_ret:(float) y_ret:(float) z_ret;  //return in percentage of image....(or do we want pixel coordinates reported?)

- (void) CreateXML;

@end
