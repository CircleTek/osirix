/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - GPL
  
  See http://homepage.mac.com/rossetantoine/osirix/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/

extern NSString				*documentsDirectory();

#import "Reports.h"
#import "DicomFile.h"

// if you want check point log info, define CHECK to the next line, uncommented:
#define CHECK NSLog(@"result code = %d", ok);

// This converts an AEDesc into a corresponding NSValue.

static id aedesc_to_id(AEDesc *desc)
{
	OSErr ok;

	if (desc->descriptorType == typeChar)
	{
		NSMutableData *outBytes;
		NSString *txt;

		outBytes = [[NSMutableData alloc] initWithLength:AEGetDescDataSize(desc)];
		ok = AEGetDescData(desc, [outBytes mutableBytes], [outBytes length]);
		CHECK;

		txt = [[NSString alloc] initWithData:outBytes encoding:[NSString defaultCStringEncoding]];
		[outBytes release];
		[txt autorelease];

		return txt;
	}

	if (desc->descriptorType == typeSInt16)
	{
		SInt16 buf;
		AEGetDescData(desc, &buf, sizeof(buf));
		return [NSNumber numberWithShort:buf];
	}

	return [NSString stringWithFormat:@"[unconverted AEDesc, type=\"%c%c%c%c\"]", ((char *)&(desc->descriptorType))[0], ((char *)&(desc->descriptorType))[1], ((char *)&(desc->descriptorType))[2], ((char *)&(desc->descriptorType))[3]];
}

@implementation Reports

+ (NSString*) getUniqueFilename:(NSManagedObject*) study
{
	return [DicomFile NSreplaceBadCharacter: [[study valueForKey:@"patientUID"] stringByAppendingFormat:@"-%@", [study valueForKey:@"id"]]];
}

- (NSString*) generateReportSourceData:(NSManagedObject*) study
{
	long x;
	
	NSManagedObjectModel	*model = [[[study managedObjectContext] persistentStoreCoordinator] managedObjectModel];

	NSArray *properties = [[[[model entitiesByName] objectForKey:@"Study"] attributesByName] allKeys];
	
	NSMutableString	*file = [NSMutableString stringWithString:@""];
	
	for( x = 0; x < [properties count]; x++)
	{
		NSString	*name = [properties objectAtIndex: x];
		[file appendString:name];
		[file appendFormat: @"%c", NSTabCharacter];
	}
	
	[file appendString:@"\r"];
	
	NSString	*shortDateString = [[NSUserDefaults standardUserDefaults] stringForKey: NSShortDateFormatString];
	NSDictionary	*localeDictionnary = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
		
	for( x = 0; x < [properties count]; x++)
	{
		NSString	*name = [properties objectAtIndex: x];
		NSString	*string;
		
		if( [[study valueForKey: name] isKindOfClass: [NSDate class]])
		{
			string = [[study valueForKey: name] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary];
		}
		else string = [[study valueForKey: name] description];
		
		if( string)
			[file appendString: [DicomFile NSreplaceBadCharacter:string]];
		else
			[file appendString: @""];
		
		[file appendFormat: @"%c", NSTabCharacter];
	}
	
	NSString	*path = [documentsDirectory() stringByAppendingFormat:@"/TEMP/Report.txt"];
	
	[[NSFileManager defaultManager] removeFileAtPath:path handler:0L];
	
	[file writeToFile: path atomically: YES];
	
	return path;
}

- (NSString *) HFSStyle: (NSString*) string
{
	return [[(NSURL *)CFURLCreateWithFileSystemPath( kCFAllocatorDefault, (CFStringRef)string, kCFURLHFSPathStyle, NO) autorelease] path];
}

- (NSString *) reportScriptBody:(NSManagedObject*) study
{
	NSString	*sourceData = [self generateReportSourceData: study];
	
	[[NSWorkspace sharedWorkspace] openFile:[documentsDirectory() stringByAppendingFormat:@"/ReportTemplate.doc"] withApplication:@"Microsoft Word" andDeactivate:NO];
	
	NSMutableString *s = [NSMutableString stringWithCapacity:1000];

	[s appendString:@"tell application \"Microsoft Word\"\n"];
	[s appendString:[NSString stringWithFormat:@"set dataSourceFile to (POSIX file \"%@\")\n", sourceData]];
	[s appendString:[NSString stringWithFormat:@"open data source data merge of active document name dataSourceFile\n"]];
	[s appendString:@"set myMerge to data merge of active document\n"];
	[s appendString:@"set destination of myMerge to send to new document\n"];
	[s appendString:@"execute data merge myMerge\n"];
	[s appendString:@"save as active document file name \"report.doc\"\n"];
	[s appendString:@"close active document saving no\n"];
	[s appendString:@"close active document saving no\n"];
	[s appendString:@"end tell\n"];
	
	NSLog( s);
	
	return s;
}

- (BOOL) createNewReport:(NSManagedObject*) study destination:(NSString*) path type:(int) type
{	
	NSString	*uniqueFilename = [Reports getUniqueFilename: study];
	
	switch( type)
	{
		case 0:
		{
			[self runScript: [self reportScriptBody: study]];
			
			NSString	*destinationFile = [NSString stringWithFormat:@"%@%@.%@", path, uniqueFilename, @"doc"];
			[[NSFileManager defaultManager] movePath:[documentsDirectory() stringByAppendingFormat:@"/report.doc"] toPath:destinationFile handler: 0L];
			[[NSWorkspace sharedWorkspace] openFile:destinationFile withApplication:@"Microsoft Word"];
			[study setValue: destinationFile forKey:@"reportURL"];
		}
		break;
		
		case 1:
		{
			NSString	*destinationFile = [NSString stringWithFormat:@"%@%@.%@", path, uniqueFilename, @"rtf"];
			[[NSFileManager defaultManager] copyPath:[documentsDirectory() stringByAppendingFormat:@"/ReportTemplate.rtf"] toPath:destinationFile handler: 0L];
			
			NSDictionary                *attr;
			NSMutableAttributedString	*rtf = [[NSMutableAttributedString alloc] initWithRTF: [NSData dataWithContentsOfFile:destinationFile] documentAttributes:&attr];
			NSString					*rtfString = [rtf string];
			NSRange						range;
			
			// SCAN FIELDS
			
			long x;
			NSManagedObjectModel	*model = [[[study managedObjectContext] persistentStoreCoordinator] managedObjectModel];
			NSArray *properties = [[[[model entitiesByName] objectForKey:@"Study"] attributesByName] allKeys];
			NSMutableString	*file = [NSMutableString stringWithString:@""];
			
			NSString	*shortDateString = [[NSUserDefaults standardUserDefaults] stringForKey: NSShortDateFormatString];
			NSDictionary	*localeDictionnary = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
			
			for( x = 0; x < [properties count]; x++)
			{
				NSString	*name = [properties objectAtIndex: x];
				NSString	*string;
				
				if( [[study valueForKey: name] isKindOfClass: [NSDate class]])
				{
					string = [[study valueForKey: name] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary];
				}
				else string = [[study valueForKey: name] description];
				
				NSRange	searchRange = NSMakeRange(0, [rtf length]);
				
				do
				{
					range = [rtfString rangeOfString: [NSString stringWithFormat:@"�%@�", name] options:0 range:searchRange];
					
					if( range.length > 0)
					{
						if( string)
						{
							[rtf replaceCharactersInRange:range withString:string];
						}
						else [rtf replaceCharactersInRange:range withString:@""];
						
						searchRange = NSMakeRange( range.location, [rtf length]-(range.location+1));
					}
				}while( range.length != 0);
			}
			
			// TODAY
			
			NSRange	searchRange = NSMakeRange(0, [rtf length]);
			
			range = [rtfString rangeOfString: [NSString stringWithString:@"�today�"] options:0 range: searchRange];
			if( range.length > 0)
			{
				[rtf replaceCharactersInRange:range withString:[[NSDate date] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary]];
			}
			
			[[rtf RTFFromRange:NSMakeRange(0, [rtf length]) documentAttributes:attr] writeToFile:destinationFile atomically:YES];
			
			[[NSWorkspace sharedWorkspace] openFile:destinationFile withApplication:@"TextEdit"];
			[study setValue: destinationFile forKey:@"reportURL"];
		}
		break;
		
		case 2:
		{
			NSMutableArray * a = [Reports pagesTemplatesList];
			NSString *destinationFile = [NSString stringWithFormat:@"%@%@.%@", path, uniqueFilename, @"pages"];
			[self createNewPagesReportForStudy:study toDestinationPath:destinationFile];
			[study setValue:destinationFile forKey:@"reportURL"];
		}
		break;
	}
	return YES;
}

// initialize it in your init method:

- (id)init
{
	self = [super init];
	if (self)
	{
		myComponent = OpenDefaultComponent(kOSAComponentType, kOSAGenericScriptingComponentSubtype);
		templateName = [NSMutableString stringWithString:@"OsiriX Report"];
	}
	return self;
}

// do the grunge work -

// the sweetly wrapped method is all we need to know:

- (void)runScript:(NSString *)txt
{
NSData *scriptChars = [txt dataUsingEncoding:[NSString defaultCStringEncoding]];
AEDesc source, resultText;
OSAID scriptId, resultId;
OSErr ok;

// Convert the source string into an AEDesc of string type.
ok = AECreateDesc(typeChar, [scriptChars bytes], [scriptChars length], &source);
CHECK;

// Compile the source into a script.
scriptId = kOSANullScript;
ok = OSACompile(myComponent, &source, kOSAModeNull, &scriptId);
AEDisposeDesc(&source);
CHECK;


// Execute the script, using defaults for everything.
resultId = 0;
ok = OSAExecute(myComponent, scriptId, kOSANullScript, kOSAModeNull, &resultId);
CHECK;

if (ok == errOSAScriptError) {
AEDesc ernum, erstr;
id ernumobj, erstrobj;

// Extract the error number and error message from our scripting component.
#if __LP64__
ok = OSAScriptError(myComponent, kOSAErrorNumber, typeSInt16, &ernum);
#else
ok = OSAScriptError(myComponent, kOSAErrorNumber, typeShortInteger, &ernum);
#endif
CHECK;
ok = OSAScriptError(myComponent, kOSAErrorMessage, typeChar, &erstr);
CHECK;

// Convert them to ObjC types.
ernumobj = aedesc_to_id(&ernum);
AEDisposeDesc(&ernum);
erstrobj = aedesc_to_id(&erstr);
AEDisposeDesc(&erstr);

txt = [NSString stringWithFormat:@"Error, number=%@, message=%@", ernumobj, erstrobj];
} else {
// If no error, extract the result, and convert it to a string for display

if (resultId != 0) { // apple doesn't mention that this can be 0?
ok = OSADisplay(myComponent, resultId, typeChar, kOSAModeNull, &resultText);
CHECK;

//NSLog(@"result thingy type = \"%c%c%c%c\"", ((char *)&(resultText.descriptorType))[0], ((char *)&(resultText.descriptorType))[1], ((char *)&(resultText.descriptorType))[2], ((char *)&(resultText.descriptorType))[3]);

txt = aedesc_to_id(&resultText);
AEDisposeDesc(&resultText);
} else {
txt = @"[no value returned]";
}
OSADispose(myComponent, resultId);
}

ok = OSADispose(myComponent, scriptId);
CHECK;
}

#pragma mark -

- (void)searchAndReplaceFieldsFromStudy:(NSManagedObject*)aStudy inString:(NSMutableString*)aString;
{
	NSManagedObjectModel *model = [[[aStudy managedObjectContext] persistentStoreCoordinator] managedObjectModel];
	NSArray *properties = [[[[model entitiesByName] objectForKey:@"Study"] attributesByName] allKeys];
	
	NSString *shortDateString = [[NSUserDefaults standardUserDefaults] stringForKey:NSShortDateFormatString];
	NSDictionary *localeDictionnary = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
	
	long x;
	for( x = 0; x < [properties count]; x++)
	{
		NSString *propertyName = [properties objectAtIndex:x];
		NSString *propertyValue;
		
		if( [[aStudy valueForKey:propertyName] isKindOfClass:[NSDate class]])
			propertyValue = [[aStudy valueForKey:propertyName] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary];
		else
			propertyValue = [[aStudy valueForKey:propertyName] description];
			
		if(!propertyValue)
			propertyValue = @"";
			
		//		� is encoded as &#xAB;
		//      � is encoded as &#xBB;
		[aString replaceOccurrencesOfString:[NSString stringWithFormat:@"&#xAB;%@&#xBB;", propertyName] withString:propertyValue options:NSLiteralSearch range:NSMakeRange(0, [aString length])];
	}
	
	// "today"
	[aString replaceOccurrencesOfString:@"&#xAB;today&#xBB;" withString:[[NSDate date] descriptionWithCalendarFormat:shortDateString timeZone:0L locale:localeDictionnary] options:NSLiteralSearch range:NSMakeRange(0, [aString length])];
}

#pragma mark -
#pragma mark Pages.app

- (NSString*)generatePagesReportScriptUsingTemplate:(NSString*)aTemplate completeFilePath:(NSString*)aFilePath;
{
	// transform path to AppleScript styled path:
	// '/Users/joris/Documents' will become ':Users:joris:Documents'
	NSMutableString *asStyledPath = [NSMutableString stringWithString:aFilePath];
	[asStyledPath replaceOccurrencesOfString:@"/" withString:@":" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [asStyledPath length])];

	NSMutableString *script = [NSMutableString stringWithCapacity:1000];
	
	[script appendString:[NSString stringWithFormat:@"set theSaveName to \"%@\"\n", asStyledPath]];
	[script appendString:@"tell application \"Pages\"\n"];
	[script appendString:[NSString stringWithFormat:@"set myDocument to make new document with properties {template name:\"%@\"}\n", aTemplate]];
	[script appendString:@"close myDocument saving in theSaveName\n"];
	[script appendString:@"end tell\n"];
	
	return script;
}

- (BOOL)createNewPagesReportForStudy:(NSManagedObject*)aStudy toDestinationPath:(NSString*)aPath;
{	
	// create the Pages file, using the template (not filling the patient's data yet)
	NSString *creationScript = [self generatePagesReportScriptUsingTemplate:templateName completeFilePath:aPath];
	[self runScript:creationScript];
	
	// decompress the gzipped index.xml.gz file in the .pages bundle
	NSTask *gzip = [[NSTask alloc] init];
	[gzip setLaunchPath:@"/usr/bin/gzip"];
	[gzip setCurrentDirectoryPath:aPath];
	[gzip setArguments:[NSArray arrayWithObjects:@"-d", @"index.xml.gz", nil]];
	[gzip launch];

	[gzip waitUntilExit];
	int status = [gzip terminationStatus];
 
	if (status == 0)
		NSLog(@"Pages Report creation. Gzip -d succeeded.");
	else
	{
		NSLog(@"Pages Report creation  failed. Cause: Gzip -d failed.");
		return NO;
	}
	[gzip release];
	// read the xml file and find & replace templated string with patient's datas
	NSString *indexFilePath = [NSString stringWithFormat:@"%@/index.xml", aPath];
	NSError *xmlError = nil;
	NSStringEncoding xmlFileEncoding = NSUTF8StringEncoding;
	NSMutableString *xmlContentString = [NSMutableString stringWithContentsOfFile:indexFilePath encoding:xmlFileEncoding error:&xmlError];

	[self searchAndReplaceFieldsFromStudy:aStudy inString:xmlContentString];
	
	if(![xmlContentString writeToFile:indexFilePath atomically:YES encoding:xmlFileEncoding error:&xmlError])
		return NO;
	
	// gzip back the index.xml file
	gzip = [[NSTask alloc] init];
	[gzip setLaunchPath:@"/usr/bin/gzip"];
	[gzip setCurrentDirectoryPath:aPath];
	[gzip setArguments:[NSArray arrayWithObjects:@"index.xml", nil]];
	[gzip launch];

	[gzip waitUntilExit];
	status = [gzip terminationStatus];
 
	if (status == 0)
		NSLog(@"Pages Report creation. Gzip succeeded.");
	else
	{
		NSLog(@"Pages Report creation  failed. Cause: Gzip failed.");
		// we don't need to return NO, because the xml has been modified. Thus, even if the file is not compressed, the report is valid...
	}
	// we don't need to gzip anything anymore 
	[gzip release];
	
	// open the modified .pages file
	[[NSWorkspace sharedWorkspace] openFile:aPath withApplication:@"Pages"];
	
	// end
	return YES;
}

+ (NSMutableArray*)pagesTemplatesList;
{
	NSArray *templateDirectoryPathArray = [NSArray arrayWithObjects:NSHomeDirectory(), @"Library", @"Application Support", @"iWork", @"Pages", @"Templates", @"My Templates", nil];
	NSString *templateDirectory = [NSString pathWithComponents:templateDirectoryPathArray];
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:templateDirectory];
	
	NSMutableArray *templatesArray = [NSMutableArray arrayWithCapacity:1];
	
	id file;	 
	while ((file = [directoryEnumerator nextObject]))
	{
		[directoryEnumerator skipDescendents];
		NSRange rangeOfOsiriX = [file rangeOfString:@"OsiriX "];
		if(rangeOfOsiriX.location==0 && rangeOfOsiriX.length==7)
		{
			// this is a template for us (we should maybe verify that it is a valid Pages template... but what ever...)
			[templatesArray addObject:[file substringFromIndex:7]];
		}
	}
	return templatesArray;
}

- (NSMutableString *)templateName;
{
	return templateName;
}

- (void)setTemplateName:(NSString *)aName;
{
	[templateName setString:aName];
	[templateName replaceOccurrencesOfString:@".template" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [templateName length])];
	[templateName insertString:@"OsiriX " atIndex:0];
	NSLog(@"setTemplateName : %@ -> %@", aName, templateName);
}

@end
