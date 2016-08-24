//
//  XCALFilter.m
//  XCAL
//
//  Copyright (c) 2012 autocalculate. All rights reserved.
//

#import "XCALFilter.h"
#import "DCMObject.h"
#import "DCMAttribute.h"
#import "DCMAttributeTag.h"
#import "DCMSequenceAttribute.h"

@implementation XCALFilter

- (void) CreateXML
{      
	//set up the XML nodes
	XMLroot = (NSXMLElement *)[NSXMLNode elementWithName:@"XCAL_Extracted_Statistics"];
	xmlDoc = [[NSXMLDocument alloc] initWithRootElement:XMLroot];
	
	//setDocumentContentKind  setMIMEType
	[xmlDoc setVersion:@"1.0"];
	[xmlDoc setCharacterEncoding:@"UTF-8"];
	
	XML_Dicom_metadata = (NSXMLElement *)[NSXMLNode elementWithName:@"XCAL_DICOM_Metadata"];
	XML_calculations = (NSXMLElement *)[NSXMLNode elementWithName:@"XCAL_Statistics"];
	
	XML_volume = (NSXMLElement *)[NSXMLNode elementWithName:@"XCAL_Volume"];
	
	[XMLroot addChild:XML_Dicom_metadata];
	[XMLroot addChild:XML_calculations];
	[XML_calculations addChild:XML_volume];
}
//--------------------------------------------
- (void) initPlugin
{
	XML_OutFilename = @"XCAL_RESULTS";
	X_Center = 0;	  //0-1, 0 is flag for invalid
	Y_Center = 0;
	Z_Center = 0;
	b_absoluteposition = false;
	
	spaceZ = 0;
	
	threshold = 0.5;
	
	strcpy(param_fname, "XCAL_Params.txt");	
	ROI_size_xy_mm = 15;
	ROI_size_z_mm = 15;
	
	cyl_radius = 22.5;
	cyl_length = 45;
	cyl_volume = M_PI * (cyl_radius * cyl_radius) * cyl_length;
	
	b_FlippedSeries = FALSE;
	show_center_pixel = FALSE;
	b_SUVMode = FALSE;
}
//-------------------------------------------------------------------------------------
- (BOOL) FindCentroid
{	
	DCMPix        *Pix;
	int z=0, x=0, y=0, curPos = 0, seg_vox_count = 0;
	float         *fImage;
	float max_pix = -10000;
	
	//first - get the max of the image
	for (z = 0; z < num_z; z++)
	{
		Pix = [PixList objectAtIndex: z];
		fImage = [Pix fImage];
		//lp accounts for rescale slope - I dont think we need to since we access MBQL, and he accessed int values - 
		//thus osirix does the conversion for us
		
		//loop over the pixels and find the max
		for (x = 0; x < num_x ; x++) //blocks out upper left
		{
			for (y = 0; y < num_y; y++)
			{
			  curPos = y * num_x + x;
	   
			  if(fImage[curPos] > max_pix)
			  {	  max_pix = fImage[curPos];
			  }
			}
		}
	  }
	  
	//find the number of voxels over the threshhold
	float max_threshold = max_pix * threshold;
	for (z = 0; z < num_z; z++)
	{
		Pix = [PixList objectAtIndex: z];
		fImage = [Pix fImage];
		
		//loop over the pixels and find the count over threshold
		for (x = 0; x < num_x ; x++) //blocks out upper left
		{
			for (y = 0; y < num_y; y++)
			{
			  curPos = y * num_x + x;
			  
			  if(fImage[curPos] > max_threshold)
			  {	  seg_vox_count++;
			  }
			 }
		  }
	  }
   
	Pix = [PixList objectAtIndex: 0];
	segmented_volume = [Pix pixelSpacingX] * [Pix pixelSpacingY] * spaceZ * seg_vox_count;
	
	//loop over and accumulate weighted sums for COM
	float row_COM = 0, col_COM = 0, slice_COM =0;
	  
	//get row, col, slice for segmented voxels
	for (z = 0; z < num_z; z++)
	{
		Pix = [PixList objectAtIndex: z];
		fImage = [Pix fImage];
		
		//loop over the pixels and find the count over threshold
		for (x = 0; x < num_x ; x++) //blocks out upper left
		{
			for (y = 0; y < num_y; y++)
			{
			  curPos = y * num_x + x;
	  
			  if(fImage[curPos] > max_threshold)
			  {	
				row_COM += x;
				col_COM += y;
				slice_COM += z;
			  }
			 }
		  }
	  }
	  
	  row_COM /= (double)seg_vox_count;	//normalize the additive values
	  col_COM /= (double)seg_vox_count;
	  slice_COM /= (double)seg_vox_count;
	    
	  centroid_x = row_COM;		  //in pixels, allot for roundoff so we dont left shift a half pixel
	  centroid_y = col_COM;
	  centroid_z = slice_COM;
	  
	  return TRUE;
}
//--------------------------------------------------------
-(void) FreeObject: (void * )object
{	
	if(object != NULL)
	{	free(object);
		object = NULL;
	}
}//--------------------------------------------------------
-(void) VerifyAllocation: (void * )object
{	
	if(object == NULL)
	{	NSRunInformationalAlertPanel(@"MEMORY ERROR!!!",[[NSString alloc] initWithFormat :@"Error in allocation (1)! Aborting!\n"], @"OK", 0L, 0L);
		exit(1);
	}
}
//--------------------------------------------
- (long) filterImage:(NSString*) menuName
{	//function called when plugin executes
	int startx, starty, startz;
	
	 if (![menuName isEqualToString:@"UW XCaliper"]) 
	 {	NSRunInformationalAlertPanel(@"NAME ERROR!!!",[[NSString alloc] initWithFormat :@"App checking for plugin named UW XCaliber\n"], @"OK", 0L, 0L);
		return -1;
	 }
	 
	[self CreateXML]; //create fresh or clear out old xml

	homeDir = getenv("HOME");
	sprintf(param_fname, "%s/Documents/OsiriX Data/XCAL_Params.txt", homeDir);
	BOOL filefound = [self ReadCommandParameterFile:param_fname];  //read input parameters
	
	if(!filefound)
	{	NSString *info = [[NSString alloc] initWithFormat :@"Input parameter \n\n%s\n\nfile cannot be parsed.", param_fname];
		NSRunInformationalAlertPanel(@"ERROR", info, @"OK", 0L, 0L);
		return -1;
	}
	
	cyl_volume = M_PI * (cyl_radius * cyl_radius) * cyl_length;
	
	if(cyl_radius <= 0 || cyl_length <= 0 || cyl_volume <= 0)
	{	NSRunInformationalAlertPanel(@"Segmented volume ERROR!!!",[[NSString alloc] initWithFormat :@"Segmented volume radius, length, or volume is <= 0! Must be positive! Aborting!\n"], @"OK", 0L, 0L);
		return -1;
	}	
	
	if(X_Center > 0 || Y_Center > 0 || Z_Center > 0)
	{ b_absoluteposition = true;  //use absolute position, not centroid
	}
	
	PixList = [viewerController pixList];
	
	curPix = [PixList objectAtIndex: 0];
	
	num_x = [curPix pwidth];
	num_y = [curPix pheight];
	num_z = [PixList count];
	
	float w = ROI_size_xy_mm / [curPix pixelSpacingX];	//15 mm
	float h = ROI_size_xy_mm / [curPix pixelSpacingY];
	spaceZ = [curPix sliceThickness];
	
	float l = ROI_size_z_mm/spaceZ;  
	
	//get pixel sizes
	int width = (int) w;  //always is smaller, so truncate, do not roundoff...
	int height = (int) h;
	int length = (int) l;
	
	//which option are we running? centroid or absolute location?
	if(b_absoluteposition == false)
	{	//then find the center
	  [self FindCentroid];
	}
	else
	{ //let the user specify where in absolute coordinates
	  centroid_x = (num_x * X_Center);
	  centroid_y = (num_y * Y_Center);
	  centroid_z = (num_z * Z_Center);
	}
	
	b_FlippedSeries = [viewerController.imageView flippedData];	//test series orientation
	
	//bfe new 11.6.12 - only allow static/wholebody scans with this tool - foor some reason header not loaded till now
	NSString* seriesNS;
	seriesNS = [self GetDICOMAttribute:@"SeriesType"];	
	char *series = [seriesNS UTF8String];
	///note only gets first item in string of say 'WHOLE BODY/IMAGE'

	//12.12.12 - we detect only the first word prior to the forward slash - so also search for the bad as well as the good cases (ie. inverse)
	//might be a parsing issue with the '/' in the string
	if(seriesNS == NULL || (strstr(series,"STATIC") == NULL && strstr(series,"WHOLE BODY") == NULL) || (strstr(series,"DYNAMIC") != NULL) || (strstr(series,"GATED") != NULL)) // want to detect inverse in case entry is silly, like volkswagon or mybody
	{
		NSRunInformationalAlertPanel(@"DICOM SeriesType ERROR!!!",[[NSString alloc] initWithFormat :@"Data set DICOM header SeriesType must be STATIC or WHOLE BODY!\nflag is: %s", series], @"OK", 0L, 0L);
		return -1;
	}
		
	//darrin has an algorithm to prevent left shift bias  - 6.22.12
	startx = ceil(centroid_x - (((float) width)/2.0));		//start of the ROI - base placement on real pixel size of ROI, not float interpretation
	starty = ceil(centroid_y - (((float) height)/2.0));	 
	startz = ceil(centroid_z - (((float) length)/2.0));	
		
	//make the ROI once, then set it in a number of slices
	NSPoint p = NSMakePoint(startx, starty);
	NSSize s = NSMakeSize(width, height);
	NSRect myRect;
	myRect.origin = p;
	myRect.size = s;

	ROI *newROI = [viewerController newROI: tROI];
	[newROI setName: @"XCAL ROI"];
	[newROI setROIRect:myRect];
	[newROI setThickness:1];  //only use 1 pixel to display - thin for accurate display
	[newROI setColor: (RGBColor){0, 65535, 0}   ];
	
	//bfe 6.21.12 - lots of new additions/fixes
	NSPoint p_axis = NSMakePoint((int)centroid_x, (int)centroid_y);	//we want to truncate so we encompass the point
	NSSize s_axis = NSMakeSize(1, 1);
	NSRect myRect2;
	myRect2.origin = p_axis;
	myRect2.size = s_axis;
	ROI *ROI_axis = [viewerController newROI: tROI];
	[ROI_axis setName: @"XCAL Center"];
	[ROI_axis setROIRect:myRect2];
	[ROI_axis setThickness:1];  //only use 1 pixel to display - thin for accurate display
	[ROI_axis setColor: (RGBColor){0, 65535, 0}   ];

	int centerslice_z = (int) (centroid_z);
	
	if(show_center_pixel) //show the center pixel bound
	{
	  [[[viewerController roiList] objectAtIndex:centerslice_z] addObject:ROI_axis];
	}
	
	if(b_FlippedSeries == FALSE)  //set correct slice based on image orientation in series
	{
	  [viewerController setImageIndex:centerslice_z];
	}
	else
	{ //(S->I)  seems to indicate reverse ordering to the slices 
	  [viewerController setImageIndex:(num_z - centerslice_z - 1)];		//(S->I)  seems to indicate reverse ordering to the slicesfor this call
	}
		
	int begin = startz+1;
	int ending = startz+length;
	float centroid_z_display = centroid_z+1;
	
	if(b_FlippedSeries == TRUE)  //set correct slice based on image orientation in series
	{
	  begin = (num_z - startz -  length)+1;
	  ending = (num_z - startz - 1)+1;
	  centroid_z_display = (num_z - centroid_z) + 1;
	}
	
	//bfe 12.13.2012 - determine if in kbql pixel or SUV mode and calculate as appropriate - if kbql then div by 1000 ---------------
	//SUVConverted hasSUV displaySUVValue
	NSString    *Units;
	if(curPix.SUVConverted)
	{	b_SUVMode = TRUE;
		Units = [NSString stringWithFormat:@"SUV"];
	}
	else
	{	b_SUVMode = FALSE;
		Units = [NSString stringWithFormat:@"kBq/ml"];
	}
	
//	if( [curPix.units isEqualToString:@"CNTS"])
//	{
//	  NSRunInformationalAlertPanel(@"PHILIPS WARNING!!!",[[NSString alloc] initWithFormat :@"This software does not correctly covert activity levels using a philips factor.\nValues will be reported in standard kBq/ml or SUV."], @"OK", 0L, 0L);
//	}
	
	//add metadata to xml file---------------
	[self Add_DICOM_XML_Attributes];
	
	//add the volume of slices - osirix does not 
	int         j,x,y; // coordinate
	double vol_mean, vol_sdev, vol_sdev_diff = 0, vol_min = 10000000, vol_max = -10000000, vol_total = 0;	//bfe 10.24.12 - adjust to have a wider range
	int num_pixels = 0;
	
	float * area_mean = NULL;
	area_mean = (float*) malloc(sizeof(float) * length);	//1 per slice
	memset(area_mean, 0, (sizeof(float) * length));	
	
	float * slice_min = NULL;
	slice_min = (float*) malloc(sizeof(float) * length);	//1 per slice
	
	float * slice_max = NULL;
	slice_max = (float*) malloc(sizeof(float) * length);	//1 per slice
	
	float * area_sdev_diff = NULL;
	area_sdev_diff = (float*) malloc(sizeof(float) * length);	//1 per slice
	memset(area_sdev_diff, 0, (sizeof(float) * length));
	
	float * area_sdev = NULL;
	area_sdev = (float*) malloc(sizeof(float) * length);	//1 per slice
	memset(area_sdev, 0, (sizeof(float) * length));	
	
	[self VerifyAllocation:area_mean];
	[self VerifyAllocation:slice_min];
	[self VerifyAllocation:slice_max];
	[self VerifyAllocation:area_sdev_diff];
	[self VerifyAllocation:area_sdev];
	
	int pixels_in_area;
	
	NSMutableArray *childnode;
	childnode = [[NSMutableArray alloc] init]; 
	//add ROI's and calc stats for slice areas
	
	//-----------------CALCULATE ACTIVITY LEVELS------------------------------------------------
	for(j = 0; j < length; j++)
	{
	  slice_min[j] = 10000000;	//init
	  slice_max[j] = -10000000;
	  
	  //add the ROI to this slice  
	  [[[viewerController roiList] objectAtIndex:startz+j] addObject:newROI];
	  //add a cross hair to centeroid point
	  
	  // collect information - area calculations
	  curPix = [PixList objectAtIndex: startz+j];	//computeROIInt
	  
	  //volume & area calcs - mean, min, max, sdev
	  float       *fImageA = [curPix fImage];
	  
	  float area_total = 0, display_area_total = 0;
	  pixels_in_area = 0;
	  
	  for (x = startx; x < startx+width; x++)
	  {
		for (y = starty; y < starty+height; y++)
		{
			double pixval = fImageA[ num_x * y + x];
			
			vol_total += pixval;
			num_pixels++;
					
			if(pixval < vol_min)
			{	vol_min = pixval;
			}
			if(pixval > vol_max)
			{	vol_max = pixval;
			}
			  
			//area calculations
			if(pixval < slice_min[j])
			{	slice_min[j] = pixval;
			}
			if(pixval > slice_max[j])
			{	slice_max[j] = pixval;
			}
			
			area_total += pixval;
			pixels_in_area++;
		  }
	  }
	  //check the area calcs against osirix calcs
	  area_mean[j] = area_total/(float)pixels_in_area;
	  
	  float       SliceROIArea_cm = (width *[curPix pixelSpacingX] * height * [curPix pixelSpacingY])/100.0;//* length * spaceZ;
	  	  
	  NSString * tempname = [NSString stringWithFormat:@"XCAL_Area_Slice%d", begin+j];
	  NSXMLElement *temp_node;
	  temp_node = (NSXMLElement *)[NSXMLNode elementWithName:tempname];
	  
	  [childnode addObject:temp_node];
	  [XML_calculations addChild:[childnode objectAtIndex:j]];
	  
	  [self AddGenerictoXMLdoc:@"Name":[newROI name]:[childnode objectAtIndex:j]];
	  [self AddGenerictoXMLdoc:@"Number_of_pixels":[NSString stringWithFormat:@"%d", pixels_in_area]:[childnode objectAtIndex:j]];
	  
	  [self AddGenerictoXMLdoc:@"Area_cm_squared":[NSString stringWithFormat:@"%.4f", SliceROIArea_cm]:[childnode objectAtIndex:j]];
	
	  display_area_total = area_total;
	  if(!b_SUVMode)
	  { //bfe - 12.13.2012 - if kbql then all units are currently in bql and need conversion div 1000 (ie SUVmode == false)
		display_area_total /= 1000.0;
		slice_min[j] /= 1000.0;
		slice_max[j] /= 1000.0;
		area_mean[j] /= 1000.0;
	  }

	  [self AddGenerictoXMLdoc:@"Sum":[NSString stringWithFormat:@"%.4f", display_area_total]:[childnode objectAtIndex:j]];
	  [self AddGenerictoXMLdoc:@"Min":[NSString stringWithFormat:@"%.4f", slice_min[j]]:[childnode objectAtIndex:j]];
	  [self AddGenerictoXMLdoc:@"Max":[NSString stringWithFormat:@"%.4f", slice_max[j]]:[childnode objectAtIndex:j]];
	  [self AddGenerictoXMLdoc:@"Mean":[NSString stringWithFormat:@"%.4f", area_mean[j]]:[childnode objectAtIndex:j]];

//	  [self AddGenerictoXMLdoc:@"Sum":[NSString stringWithFormat:@"%.4f", area_total/1000.0]:[childnode objectAtIndex:j]];
//	  [self AddGenerictoXMLdoc:@"Min":[NSString stringWithFormat:@"%.4f", slice_min[j]/1000.0]:[childnode objectAtIndex:j]];
//	  [self AddGenerictoXMLdoc:@"Max":[NSString stringWithFormat:@"%.4f", slice_max[j]/1000.0]:[childnode objectAtIndex:j]];
//	  [self AddGenerictoXMLdoc:@"Mean":[NSString stringWithFormat:@"%.4f", area_mean[j]/1000.0]:[childnode objectAtIndex:j]];
  }
	
	vol_mean = vol_total/num_pixels;
	
	//sdev calc - have to run another loop after we have the means
	for(j = 0; j < length; j++)
	{
	  curPix = [PixList objectAtIndex: startz+j];
		//volume calcs
	  float       *fImageA = [curPix fImage];
	  
	  for (x = startx; x < startx+width; x++)
	  {
		for (y = starty; y < starty+height; y++)
		{
		  // get pixel
		  double pixval = fImageA[ num_x * y + x];

		  vol_sdev_diff += pow((pixval - vol_mean), 2);
		  area_sdev_diff[j] += pow((pixval - area_mean[j]), 2);
		  }
	  }
	  
	  area_sdev[j] = sqrt(area_sdev_diff[j]/(float)pixels_in_area);	//same pixels per slice area
	  
	  if(!b_SUVMode)
	  { //bfe - 12.13.2012 - if kbql then all units are currently in bql and need conversion div 1000 (ie SUVmode == false)
		area_sdev[j] /= 1000.0;
	  }
	  //move area xml write to here now that sdev calculated
	  [self AddGenerictoXMLdoc:@"SDev":[NSString stringWithFormat:@"%.4f", area_sdev[j]]:[childnode objectAtIndex:j]];
	  
	}
	vol_sdev = sqrt(vol_sdev_diff/(float)num_pixels);
	
	//-----------------------------------------------------------------
	
	if(!b_SUVMode)
	{ //bfe - 12.13.2012 - if kbql then all units are currently in bql and need conversion div 1000 (ie SUVmode == false)
	  vol_total /= 1000.0;
	  vol_min /= 1000.0;
	  vol_max /= 1000.0;
	  vol_mean /= 1000.0;
	  vol_sdev /= 1000.0;
	}
	//else if( [curPix.units isEqualToString:@"CNTS"]) return pixelMouseValue * curPix.philipsFactor;
	
	[self FreeObject:area_mean];
	[self FreeObject:slice_min];
	[self FreeObject:slice_max];
	[self FreeObject:area_sdev_diff];
	[self FreeObject:area_sdev];
	
	//volume calculations
	float       SliceROIVolume_cm = (width *[curPix pixelSpacingX] * height * [curPix pixelSpacingY] * length * spaceZ )/1000.0;  //bfe 10.24.12 fix bug - off by factor of 10
	float		volume_length = length * spaceZ;
	
	[self AddtoXMLdoc_volume:@"Name":[newROI name]];
	[self AddtoXMLdoc_volume:@"Number_of_pixels":[NSString stringWithFormat:@"%d", num_pixels]];
	[self AddtoXMLdoc_volume:@"X_Start":[NSString stringWithFormat:@"%d", startx]];
	[self AddtoXMLdoc_volume:@"X_Pixels":[NSString stringWithFormat:@"%d", width]];
	[self AddtoXMLdoc_volume:@"Y_Start":[NSString stringWithFormat:@"%d", starty]];
	[self AddtoXMLdoc_volume:@"Y_Pixels":[NSString stringWithFormat:@"%d", height]];
	[self AddtoXMLdoc_volume:@"Z_Start":[NSString stringWithFormat:@"%d", begin]];
	[self AddtoXMLdoc_volume:@"Number_of_slices":[NSString stringWithFormat:@"%d", length]];
	
	[self AddtoXMLdoc_volume:@"Volume_cm_cubed":[NSString stringWithFormat:@"%.4f", SliceROIVolume_cm]];
	[self AddtoXMLdoc_volume:@"Volume_length_mm":[NSString stringWithFormat:@"%.4f", volume_length]];
	[self AddtoXMLdoc_volume:@"Volume_width_mm":[NSString stringWithFormat:@"%.4f", width *[curPix pixelSpacingX]]];
	[self AddtoXMLdoc_volume:@"Volume_height_mm":[NSString stringWithFormat:@"%.4f", height * [curPix pixelSpacingY]]];
	
	if(!b_SUVMode) 
	{	//special kBq display - cant have '/' in xml
		[self AddtoXMLdoc_volume:@"Activity_units":[NSString stringWithFormat:@"%s","kBq_per_ml"]]; //bfe 12.13.12 - tell user what units are
	}
	else
	{	[self AddtoXMLdoc_volume:@"Activity_units":[NSString stringWithFormat:@"%s", "SUV"]]; //bfe 12.13.12 - tell user what units are
	}
	
	[self AddtoXMLdoc_volume:@"Sum":[NSString stringWithFormat:@"%.4f", vol_total]];
	[self AddtoXMLdoc_volume:@"Min":[NSString stringWithFormat:@"%.4f", vol_min]];
	[self AddtoXMLdoc_volume:@"Max":[NSString stringWithFormat:@"%.4f", vol_max]];
	[self AddtoXMLdoc_volume:@"Mean":[NSString stringWithFormat:@"%f", vol_mean]];
	[self AddtoXMLdoc_volume:@"SDev":[NSString stringWithFormat:@"%f", vol_sdev]];
		
	[self AddtoXMLdoc_volume:@"Threshold_volume_cm_cubed":[NSString stringWithFormat:@"%.4f", SliceROIVolume_cm]];//bfe 10.31.12
	[self AddtoXMLdoc_volume:@"Threshold_of":[NSString stringWithFormat:@"%.4f", threshold]];//bfe 10.31.12
	[self AddtoXMLdoc_volume:@"Known_cylinder_radius_cm":[NSString stringWithFormat:@"%.2f", cyl_radius]];//bfe 10.31.12
	[self AddtoXMLdoc_volume:@"Known_cylinder_length_cm":[NSString stringWithFormat:@"%.2f", cyl_length]];//bfe 10.31.12
		
	//and write it to xml------------------------------------
		
	//need to get users home directory!
    NSData *xmlData = [xmlDoc XMLDataWithOptions:NSXMLNodePrettyPrint];
	XML_OutFilename = [self GetDICOMAttribute:@"StudyDescription"];	//replace the generic with something unique to this series
	//check to make sure something valid in name.....
	
	if (XML_OutFilename == NULL) 
	{
	  XML_OutFilename = [self GetDICOMAttribute:@"ImplementationVersionName"];	
	}	
	if (XML_OutFilename == NULL) 
	{
	  XML_OutFilename = [self GetDICOMAttribute:@"Manufacturer"];	//should always have this
	}
	if (XML_OutFilename == NULL) 
	{
	  XML_OutFilename =  @"XCAL_RESULTS_noname";
	}

	NSDateFormatter *formatter;
	NSString        *dateString;

	formatter = [[NSDateFormatter alloc] init];
	//[formatter setDateFormat:@"dd-MM-yyyy HH:mm"];
	[formatter setDateFormat:@"MMddyyyy_HHmmss"];

	dateString = [formatter stringFromDate:[NSDate date]];

	[formatter release];
	 XML_OutFilename = [XML_OutFilename stringByAppendingString:[[NSString alloc] initWithFormat :@"_%@", dateString]];

	NSString *outfile = [[NSString alloc] initWithFormat :@"%s%@/%@.xml", homeDir, XCAL_Directory, XML_OutFilename];
	NSString *outfolderNS = [[NSString alloc] initWithFormat :@"%s%@", homeDir, XCAL_Directory] ;
	
	[self GenerateFolder:[outfolderNS UTF8String]];  //create if needed - warning is OK
	
	if (access([outfile UTF8String], F_OK) == 0)
	{	//if file exists, remove it - otherwise we add the data twice to the file
		char cmd[256];
		
		///should ask user if we want to delete file, or else append a date/time stamp to it
	  	sprintf(cmd, "rm -f '%s'", [outfile UTF8String]);//needs single quotes or will not work
	  	system(cmd);
	}
	
	[xmlData writeToFile:outfile atomically:YES];
	
	// show information
	//------------------------------------------------

	NSString    *Volume_stats = [NSString stringWithFormat:@"____________________________________\n\n"
					"ROI Statistics\n\n"		
					"Mean: %.1f %@\nSDev: %.2f %@\n"
					"Min: %.1f %@\nMax: %.1f %@\n"
					"Total: %.1f %@\nVolume: %.2f cm^3\n"			
					"X width: %.1f mm\nY height: %.1f mm\nZ length: %.1f mm\n"
					"Num voxels in 3D ROI: %d\n"
					"Volume: slices %d to %d\nName: '%@'\n"
					"____________________________________",
					vol_mean, Units, vol_sdev, Units, 
					vol_min, Units, vol_max, Units,
					vol_total, Units, SliceROIVolume_cm, 
					width *[curPix pixelSpacingX], height * [curPix pixelSpacingY], volume_length, 
					num_pixels,
					begin, ending, [newROI name]];
							
	NSString    *Cylinder_stats = [NSString stringWithFormat:@"Known cylinder volume: %.1f cm^3\n(%.1f cm radius with %.1f cm length)\nThreshold volume: %.1f cm^3 at %.2f threshold\nThreshold volume / cylinder: %.2f", (cyl_volume/1000.0), 
	cyl_radius, cyl_length, (segmented_volume/1000.0), threshold, segmented_volume/cyl_volume];
	NSString    *Centroid_stats;
	NSString    *User_info = [NSString stringWithFormat:@"Volume computed using whole voxels only.\nPlease see manual for details."];
	
	
	if(b_absoluteposition == false)
	{	//Centroid_stats = [NSString stringWithFormat:@"Centroid calculated:\nx: %.2f  start x: %d\ny: %.2f  start y: %d\nz: %.2f  start z: %d", centroid_x, startx, centroid_y, starty, centroid_z_display, startz+1];
		Centroid_stats = [NSString stringWithFormat:@"Centroid Statistics [note: first index = 0]\n\nX pixels: %.1f  start x: %d	  width: %d\nY pixels: %.1f  start y: %d	  height: %d\nZ pixels: %.1f  start z: %d	  length %d", centroid_x, startx, width, centroid_y, starty, height, centroid_z_display, begin, length];
	}
	else
	{	Centroid_stats = [NSString stringWithFormat:@"Absolute positioning:\nx: %.1f  start x: %d\ny: %.1f  start y: %d\nz: %.1f  start z: %d", centroid_x, startx, centroid_y, starty, centroid_z_display, startz+1];
	}
								 
	//pauls sanity check for threshold
	if((fabs(1.0 - (segmented_volume/cyl_volume))) > .1)
	{
	  NSRunInformationalAlertPanel(@"VOLUMES DIFFER",[[NSString alloc] initWithFormat :@"Expected volume and calculated volume differ significantly (.1) with threshold %.2f!\n\nKnown cylinder volume: %.1f cm^3\n(%.1f cm radius with %.1f cm length)\nThreshold volume: %.1f cm^3\nThreshold volume / cylinder: %.2f", threshold, (cyl_volume/1000.0), cyl_radius, cyl_length, (segmented_volume/1000.0), segmented_volume/cyl_volume], @"OK", 0L, 0L);
	}
								 
	//tell user we wrote an xml file!
	NSString *info = [[NSString alloc] initWithFormat :@"Created XML file %@\n%@\n\n%@\n\n%@\n\n%@", outfile, Volume_stats, Centroid_stats, Cylinder_stats, User_info];
	NSRunInformationalAlertPanel(@"UW Excaliper ROI Toolkit",info, @"OK", 0L, 0L);

	[viewerController needsDisplayUpdate];
	
	//reset any flags that may be needed in next iteration of plugin
	//the init is only called first time -  so these could be obsolete in a secondary run
	b_absoluteposition = false;
	
	X_Center = 0;	  //0-1
	Y_Center = 0;
	Z_Center = 0;
	threshold = 0.1;
	
	ROI_size_xy_mm = 15;
	ROI_size_z_mm = 15;
	
	   return 0;
}

/*
*  Formula K(SUV)=K(Bq/cc)*(Wt(kg)/Dose(Bq)*1000 cc/kg 
*						  
*  Where: K(Bq/cc) = is a pixel value calibrated to Bq/cc and decay corrected to scan start time
*		 Dose = the injected dose in Bq at injection time (This value is decay corrected to scan start time. The injection time must be part of the dataset.)
*		 Wt = patient weight in kg
*		 1000=the number of cc/kg for water (an approximate conversion of patient weight to distribution volume)


- (float) getBlendedSUV
{
	if( [[blendingView curDCM] SUVConverted]) return blendingPixelMouseValue;
	
	if( [[[blendingView curDCM] units] isEqualToString:@"CNTS"]) return blendingPixelMouseValue * [[blendingView curDCM] philipsFactor];
	return blendingPixelMouseValue * [[blendingView curDCM] patientsWeight] * 1000. / ([[blendingView curDCM] radionuclideTotalDoseCorrected] * [curDCM decayFactor]);
}

- (float)getSUV
{
	if( curDCM.SUVConverted) return pixelMouseValue;
	
	if( [curDCM.units isEqualToString:@"CNTS"]) return pixelMouseValue * curDCM.philipsFactor;
	else return pixelMouseValue * curDCM.patientsWeight * 1000.0f / (curDCM.radionuclideTotalDoseCorrected * [curDCM decayFactor]);
}

DCMPix

	if( curDCM.displaySUVValue )
								{
									if( [curDCM hasSUV] == YES && curDCM.SUVConverted == NO)
									{
										[tempString3 appendFormat: NSLocalizedString( @"SUV: %.2f", @"SUV: Standard Uptake Value - No special characters for this string, only ASCII characters."), [self getSUV]];
									}
								}
*/

//-------------------------------------------------------------------------------------
- (BOOL) PopulateCommandLineItemFromFile:(char *) key: (char *) value
{ /*Command parameters that control type & variation of the run*/

  //-------------- chararacteristics---------------
  if(strcmp(key, "X_Center") == 0)
  {
  	X_Center = atof(value);
  }
  else if(strcmp(key, "Y_Center") == 0)
  {
  	Y_Center = atof(value);
  }
  else if(strcmp(key, "Z_Center") == 0)
  {
  	Z_Center = atof(value);
  }
  else if(strcmp(key, "SizeROI_xy_mm") == 0)
  {
  	ROI_size_xy_mm = atof(value);
  }
  else if(strcmp(key, "SizeROI_z_mm") == 0)
  {
  	ROI_size_z_mm = atof(value);
  }
  else if(strcmp(key, "Centroid_Threshold") == 0)
  {
  	threshold = atof(value);
  }
  else if(strcmp(key, "cylinder_radius") == 0)
  {
  	cyl_radius = atof(value);
  }
  else if(strcmp(key, "cylinder_length") == 0)
  {
  	cyl_length = atof(value);
  }
  else if(strcmp(key, "show_center_pixel") == 0)
  {
	int val = atoi(value);
	if(val == 1)
	{
	  show_center_pixel = TRUE;
	}
  }
  else if(strcmp(key, "XCAL_Directory") == 0)
  {	  //muzi says we can get the location of the OSiriX Data folder from the osrix preferences
  	  if (strlen(value) >= 256) 
	  {
		NSRunInformationalAlertPanel(@"ERROR",@" PopulateCommandLineItemFromFile> !!! Error: key-value '%s' should contain less than 256 characters", @"OK", 0L, 0L);
		return FALSE;
	  }
	  
	  XCAL_Directory = [[NSString alloc] initWithFormat :@"%s", value];
  }
  else
  {
	NSString *info = [[NSString alloc] initWithFormat :@"PopulateCommandLineItemFromFile> Key \n\n%s\n\n not found.", key];
	NSRunInformationalAlertPanel(@"ERROR", info, @"OK", 0L, 0L);
	//return FALSE;	//keep running in this case - will just use defaults
  }
  
  return TRUE;
}
//-------------------------------------------------------------------------------------
-(void) RemoveTrailingSpaces:(char *) value
{	//trailing spaces, tabs

	int slen = strlen(value);
	int i;
	for(i = slen-1; i >= 0; i--)
	{
		if(value[i] != ' ' && value[i] != '\t')		//look for the last character that is not a space or tab
		{
			break;
		}
	}
	if(i != slen-1)
	{
		value[i+1] = '\0';	//and set the end of string there
	}
}
//--------------------------------------------------------
-(void) GenerateFolder:(char *) OutputFolderName
{	
	//NOTE: Currently only MAC/Unix tested
	char cmd[256];
	
	if (access(OutputFolderName, F_OK) == 0)
	{	//if folder exists, leave it
	}
	else
	{
	  // make it fresh
	  sprintf(cmd, "mkdir '%s'", OutputFolderName);	
	  system(cmd);
	}
}
//-------------------------------------------------------------------------------------
- (BOOL)  ReadCommandParameterFile:(char *) filename
{	//might work better in a .c file and linked in
  FILE *f;
  char line[256], *c, * key, * value;
  line[0] = '\0';
  
  f = fopen(filename,"r");
  
  if(f == NULL) 
  {
	  NSString *info = [[NSString alloc] initWithFormat :@"ReadParameterFile> File \n\n%s\n\n can not be opened.", filename];
	  NSRunInformationalAlertPanel(@"ERROR", info, @"OK", 0L, 0L);
	  return FALSE;
  }
  
  while ((!feof(f))) 
  {
    c = (char *) fgets(line, 256, f);
	
	/*we parse looking for the equal sign, then our data is between that and the newline*/
	
	if(c != NULL)											  /*null on last read*/
	{
	  key = strtok (line,"=\n");
	  
	  if(key != NULL && key[0] != '#')	//look for a comment beginning at the start of line
	  {
		//value = strtok (NULL," \n#");							  /*NULL continues reading from same string*/
		value = strtok (NULL,"\t\n#");							  /*NULL continues reading from same string*/
		//may want to allow a comment field at end of line, say #
		
		[self RemoveTrailingSpaces:value ];
		
		if(value != NULL)
		{  
		if(([self PopulateCommandLineItemFromFile: key: value]) == FALSE)
		  {
				NSRunInformationalAlertPanel(@"ERROR", @"Error: Invalid parameter in command input file!", @"OK", 0L, 0L);
				fclose(f);	
				return FALSE;
		  }
		}
	  }
	}
  }
  
  fclose(f);	
  
  //TODO: ERROR CHECK INPUT

  return TRUE;
}
//-------------------------------------------------------------
- (void) Add_DICOM_XML_Attributes
{ 
	[self AddtoXMLdocDICOM:@"SeriesDescription"];
	[self AddtoXMLdocDICOM:@"Manufacturer"];
	
	[self AddtoXMLdocDICOM:@"SOPInstanceUID"];
	[self AddtoXMLdocDICOM:@"SeriesInstanceUID"]; //bfe 10.31.12
	
	[self AddtoXMLdocDICOM:@"SeriesTime"];
	[self AddtoXMLdocDICOM:@"AcquisitionTime"];
	[self AddtoXMLdocDICOM:@"PatientsSex"];
	
	[self AddtoXMLdocDICOM:@"PatientsSize"];
	[self AddtoXMLdocDICOM:@"PatientsWeight"];
	
	//sequenced items
	[self AddtoXML_Nesteditem_DICOM:@"0018,0031":@"Radiopharmaceutical":@"RadiopharmaceuticalInformationSequence":XML_Dicom_metadata];
	[self AddtoXML_Nesteditem_DICOM:@"0018,1076":@"RadionuclidePositronFraction":@"RadiopharmaceuticalInformationSequence":XML_Dicom_metadata];
	[self AddtoXML_Nesteditem_DICOM:@"0018,1075":@"RadionuclideHalfLife":@"RadiopharmaceuticalInformationSequence":XML_Dicom_metadata];
	[self AddtoXML_Nesteditem_DICOM:@"0018,1072":@"RadiopharmaceuticalStartTime":@"RadiopharmaceuticalInformationSequence":XML_Dicom_metadata];
	[self AddtoXML_Nesteditem_DICOM:@"0018,1074":@"RadionuclideTotalDose":@"RadiopharmaceuticalInformationSequence":XML_Dicom_metadata];
	
	[self AddtoXMLdocDICOM:@"ActualFrameDuration"];
	[self AddtoXMLdocDICOM:@"Units"];
	[self AddtoXMLdocDICOM:@"DecayCorrection"];
	[self AddtoXMLdocDICOM:@"FrameReferenceTime"];
	[self AddtoXMLdocDICOM:@"DecayFactor"];
	//PhilipsSUVfactor	
	//Philipscountstoactivityconcentrationfactor
	
	[self AddtoXMLdocDICOM:@"ImagePositionPatient"];
	[self AddtoXMLdocDICOM:@"SliceLocation"];
	[self AddtoXMLdocDICOM:@"StudyDate"];
	[self AddtoXMLdocDICOM:@"InstitutionName"];
	//Manufacturers model name - DNE
	[self AddtoXMLdocDICOM:@"SliceThickness"];
	[self AddtoXMLdocDICOM:@"ReconstructionDiameter"];
	[self AddtoXMLdocDICOM:@"Rows"];
	[self AddtoXMLdocDICOM:@"Columns"];	//bfe added 5.2.11

	[self AddtoXMLdocDICOM:@"PixelSpacing"];
	[self AddtoXMLdocDICOM:@"CorrectedImage"];
	[self AddtoXMLdocDICOM:@"ReconstructionMethod"];
}
//-------------------------------------------------------------
- (void) AddtoXMLdoc_volume:(NSString*) key: (NSString*) value
{ //for calculation
	  [self AddGenerictoXMLdoc:key:value:XML_volume];
}
//-------------------------------------------------------------
- (void) AddtoXMLdoc_calculation:(NSString*) key: (NSString*) value
{ //for calculation
	  [self AddGenerictoXMLdoc:key:value:XML_calculations];
}
//-------------------------------------------------------------
- (void) AddtoXMLdocDICOM:(NSString*) metakey
{ //for dicom meta tag
  [self AddtoXMLdoc:metakey:XML_Dicom_metadata];
}
//-------------------------------------------------------------
- (void) AddGenerictoXMLdoc:(NSString*) key: (NSString*) value: (NSXMLElement *)XMLparent
{ //for any thing
		NSXMLElement *Element = [NSXMLNode elementWithName:key];
		[Element setStringValue:value];
		[XMLparent addChild:Element];
}
//-------------------------------------------------------------
- (void) AddtoXMLdocRoot:(NSString*) metakey
{ //for dicom meta tag
  [self AddtoXMLdoc:metakey:XMLroot];
}
//-------------------------------------------------------------
- (void) AddtoXMLdoc:(NSString*) metakey: (NSXMLElement *)XMLparent
{
	//get a dicom attribute metaheader value
	NSString        *file_path = [curPix sourceFile];
	NSString        *dicomTag = metakey;
 
	DCMObject       *dcmObj = [DCMObject objectWithContentsOfFile:file_path decodingPixelData:NO];
	DCMAttributeTag *tag = [DCMAttributeTag tagWithName:dicomTag];//initWithName	initWithTagString
	if (!tag) tag = [DCMAttributeTag tagWithTagString:dicomTag]; 

	NSString        *val;
	DCMAttribute    *attr;
 
	if (tag && tag.group && tag.element)
	{
		attr = [dcmObj attributeForTag:tag];
		
		if([metakey isEqualToString:@"PixelSpacing"])
		{		//get pixel x and pixel y, note the DICOM style deliminator
		  val = [[NSString alloc] initWithFormat :@"%@/%@", [[attr values] objectAtIndex:0], [[attr values] objectAtIndex:1]];
		}
		else
		{
		  val = [[attr value] description];
		}
 
	}
	
	NSXMLElement *Element = [NSXMLNode elementWithName:dicomTag];
	[Element setStringValue:val];
	[XMLparent addChild:Element];
}
//-------------------------------------------------------------
- (NSString*) GetDICOMAttribute:(NSString*) metakey
{
	//get a dicom attribute metaheader value
	NSString        *file_path = [curPix sourceFile];
	NSString        *dicomTag = metakey;
 
	DCMObject       *dcmObj = [DCMObject objectWithContentsOfFile:file_path decodingPixelData:NO];
	DCMAttributeTag *tag = [DCMAttributeTag tagWithName:dicomTag];//initWithName	initWithTagString
	if (!tag) tag = [DCMAttributeTag tagWithTagString:dicomTag]; 

 
	NSString        *val;
	DCMAttribute    *attr;
 
	if (tag && tag.group && tag.element)
	{
		attr = [dcmObj attributeForTag:tag];
 
		val = [[attr value] description];
	}
	  return val;
}
//-------------------------------------------------------------
- (void) AddtoXML_Nesteditem_DICOM:(NSString*) GroupElement: (NSString*) metakey: (NSString*) parentmetakey:(NSXMLElement *)XMLparent
{
	//get a dicom attribute metaheader value from a sequenced item
	NSString        *file_path = [curPix sourceFile];
	DCMObject       *dcmObj = [DCMObject objectWithContentsOfFile:file_path decodingPixelData:NO];
	NSArray * seq = [(DCMSequenceAttribute *)[dcmObj attributeWithName:parentmetakey] sequenceItems];
	//then we can search the sequence for the item
	 
    DCMAttributeTag *tag;
    DCMObject * obj;
	for  ( NSDictionary *key in seq ) 
	{
	  obj = [key objectForKey:@"item"];
	  
	  tag = [[obj attributes] objectForKey:GroupElement];
	
	}
 
	NSString        *val;
	val = [tag value];

	NSXMLElement *Element = [NSXMLNode elementWithName:metakey];
	[Element setStringValue:val];
	[XMLparent addChild:Element];		
}
//need a nested item metaheader adder!
@end
