//
//  MapCouchbaseDataModel.m
//  Wildflowers of Detroit Iphone
//
//  Created by Deep Winter on 2/1/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "MapCouchbaseDataModel.h"
#import "AppDelegate.h"
#import "RhusDocument.h"
#import "DeviceUser.h"
#import "RHSettings.h"


@implementation MapCouchbaseDataModel

@synthesize database;
@synthesize query;


//- (id) initWithBlock:( void ( ^ )() ) didStartBlock {
- (id) init {
    // Start the Couchbase Mobile server:
    // gCouchLogLevel = 1;
    [CouchbaseMobile class];  // prevents dead-stripping
    CouchEmbeddedServer* server;
    
    if(![RHSettings useRemoteServer]){
        server = [[CouchEmbeddedServer alloc] init];
    } else {
        server = [[CouchEmbeddedServer alloc] initWithURL: [NSURL URLWithString: [RHSettings couchRemoteServer]]];
        /*
         Set Admin Credential Somehow??
        server.couchbase.adminCredential = [NSURLCredential credentialWithUser:@"winterroot" password:@"dieis8835nd" persistence:NSURLCredentialPersistenceForSession];
         */
    }
    
#if INSTALL_CANNED_DATABASE
    NSString* dbPath = [[NSBundle mainBundle] pathForResource: [RHSettings databaseName] ofType: @"couch"];
    NSAssert(dbPath, @"Couldn't find "kDatabaseName".couch");
    [server installDefaultDatabase: dbPath];
#endif
    
    BOOL started = [server start: ^{  // ... this block runs later on when the server has started up:
        if (server.error) {
            [self showAlert: @"Couldn't start Couchbase." error: server.error fatal: YES];
            return;
        }
        
       // NSError ** outError; 
       // NSString * version = [server getVersion: outError];
      //  NSArray * databases = [server getDatabases];
        self.database = [server databaseNamed: [RHSettings databaseName]];
        NSAssert(database, @"Database Is NULL!");
        
        
        if(![RHSettings useRemoteServer]){
            // Create the database on the first run of the app.
            NSError* error;
            if (![self.database ensureCreated: &error]) {
                [self showAlert: @"Couldn't create local database." error: error fatal: YES];
                return;
            }
            
        }
        
        database.tracksChanges = YES;
                
      //  NSLog(@"%@", @"Calling did start block");
       // didStartBlock();
        
        //Compile views
        CouchDesignDocument* design = [database designDocumentWithName: @"design"];
        NSAssert(design, @"Couldn't find design document");
        design.language = kCouchLanguageJavaScript;
        /*
        [design defineViewNamed: @"detailDocuments"
                            map: @"function(doc) { emit([doc.created_at], [doc._id, doc.reporter, doc.comment, doc.medium, doc.created_at] );}"];
        */
         
        [design defineViewNamed: @"deviceUserGalleryDocuments"
                            map: @"function(doc) { emit([doc.deviceuser_identifier, doc.created_at],{'id':doc._id, 'thumb':doc.thumb, 'medium':doc.medium, 'latitude':doc.latitude, 'longitude':doc.longitude, 'reporter':doc.reporter, 'comment':doc.comment, 'created_at':doc.created_at} );}"];
        
        design.language = kCouchLanguageJavaScript;
        [design defineViewNamed: @"galleryDocuments"
                            map: @"function(doc) { emit(doc.created_at,{'id':doc._id, 'thumb':doc.thumb, 'medium':doc.medium, 'latitude':doc.latitude, 'longitude':doc.longitude, 'reporter':doc.reporter, 'comment':doc.comment, 'created_at':doc.created_at, 'deviceuser_identifier':doc.deviceuser_identifier } );}"];

        design.language = kCouchLanguageJavaScript;
        [design defineViewNamed: @"detailDocuments"
                            map: @"function(doc) { emit(doc.created_at, [doc._id, doc.reporter, doc.comment, doc.medium, doc.created_at] );}"];
        [design saveChanges];
        
        //TODO: Reorganize to use a block
        [(AppDelegate *) [[UIApplication sharedApplication] delegate] doneStartingUp];
        
    }];
    NSLog(@"%@", @"Started...");
    NSAssert(started, @"didnt start");
    
    return self;
    
}


+ (NSData *) getDocumentThumbnailData: (NSString *) key {
    CouchDocument* doc = [[self.instance database] documentWithID: key];
    CouchModel * model = [[CouchModel alloc] initWithDocument:doc];
    CouchAttachment * thumbnail = [model attachmentNamed:@"thumb.jpg"];
    if(thumbnail != nil){
        return thumbnail.body;
    } else {
        return nil;
    }
}

+ (NSData *) getDocumentImageData: (NSString *) key {
    CouchDocument* doc = [[self.instance database] documentWithID: key];
    CouchModel * model = [[CouchModel alloc] initWithDocument:doc];
    CouchAttachment * thumbnail = [model attachmentNamed:@"medium.jpg"];
    if(thumbnail != nil){
        return thumbnail.body;
    } else {
        return nil;
    }
}


- (NSArray *) runQuery: (CouchQuery *) couchQuery {
    RESTOperation * op = [couchQuery start];

    CouchQueryEnumerator * enumerator = [couchQuery rows];
    
    NSLog(@"op = %@", op.dump);
    if(!enumerator){
        return [NSArray array];
    }
    NSLog(@"count = %i", [enumerator count]);
  
    CouchQueryRow * row;
    NSMutableArray * data = [NSMutableArray array];
    while( (row =[enumerator nextRow]) ){
        
        
        //Fix Image Attachments
        //TODO: This code can be removed once we are reasonably certain everything has been transformed
        BOOL docNeedsSave = false;
        CouchDocument * doc = row.document;
        NSMutableDictionary * newProperties = [doc.properties mutableCopy ];

        /*
        if( ([row.value objectForKey:@"thumb"] == NULL) || ([row.value objectForKey:@"thumb"] == @"") ){
            NSString * docId = [row.value objectForKey:@"id"];
            NSData * imageData = [MapCouchbaseDataModel getDocumentThumbnailData:docId];
            if(imageData != nil){
                NSData * thumb = imageData;
                [newProperties setValue:[RESTBody base64WithData:thumb] forKey:@"thumb"];
                docNeedsSave = true;
            } else if([doc.properties objectForKey:@"thumb-android0.1"]){
                [newProperties setValue:[doc.properties objectForKey:@"thumb-android0.1"] forKey:@"thumb"];
            }
        }    
        
        
        if([row.value objectForKey:@"medium"] == NULL || [row.value objectForKey:@"medium"] == @""){
            NSData * imageData = [MapCouchbaseDataModel getDocumentImageData:[row.value objectForKey:@"id"]];
            if(imageData != nil){
                NSData * mediumImage = imageData;
                [newProperties setValue:[RESTBody base64WithData:mediumImage] forKey:@"medium"];
                docNeedsSave = true;
            } else if([doc.properties objectForKey:@"medium-android0.1"]){
                [newProperties setValue:[doc.properties objectForKey:@"medium-android0.1"] forKey:@"medium"];
            }
        }
    
        
        if(docNeedsSave){
            CouchRevision* latest = doc.currentRevision;
            //  NSLog(@"%@", [newProperties debugDescription]);
            NSLog(@"Fixing Document");
            NSLog(@"%@", [row.value objectForKey:@"id"] );
            RESTOperation* op = [latest putProperties:newProperties];
            [op start];
            [op wait]; //make it synchronous
        }
        */
        

        //Translate the Base64 data into a UIImage
        if([newProperties objectForKey:@"thumb"] != NULL && [newProperties objectForKey:@"thumb"] != @"" ){
            NSString * base64 = [newProperties objectForKey:@"thumb"];
          //  NSLog(@"%@", [row.value objectForKey:@"id"] );
            NSData * thumb = [RESTBody dataWithBase64:base64];
            if(thumb != NULL && [thumb length]){
                [newProperties setObject:[UIImage imageWithData:thumb]
                          forKey:@"thumb"];
            } else {
                [newProperties removeObjectForKey:@"thumb"];
            }
        } else {
            [newProperties removeObjectForKey:@"thumb"];
        }
        
        
        if([newProperties objectForKey:@"medium"] != NULL && [newProperties objectForKey:@"medium"] != @"" ){
            NSString * base64 = [newProperties objectForKey:@"medium"];
          //  NSLog(@"%@", [row.value objectForKey:@"id"] );
            NSData * medium = [RESTBody dataWithBase64:base64];
            if(medium != NULL && [medium length]){
                [newProperties setObject:[UIImage imageWithData:medium]
                                  forKey:@"medium"];
            } else {
                [newProperties removeObjectForKey:@"medium"];
                
            }
        } else {
            [newProperties removeObjectForKey:@"medium"];
        }
        
        
        //give em the data
        [data addObject: [[RhusDocument alloc] initWithDictionary: [NSDictionary dictionaryWithDictionary: newProperties]]];
    }
    return data;
    
}
    

+ (NSArray *) getUserGalleryDocumentsWithStartKey: (NSString *) startKey 
                                         andLimit: (NSInteger) limit 
                                         andUserIdentifer: (NSString *) userIdentifier {
    
    //Create view;
    CouchDatabase * database = [self.instance database];
    CouchDesignDocument* design = [database designDocumentWithName: @"design"];
    NSAssert(design, @"Couldn't find design document");
  
    CouchQuery * query = [design queryViewNamed: @"deviceUserGalleryDocuments"]; //asLiveQuery];

    query.descending = YES;
    query.endKey = [NSArray arrayWithObjects:userIdentifier, nil];
    query.startKey = [NSArray arrayWithObjects:userIdentifier, [NSDictionary dictionary], nil];
    
    NSArray * r = [(MapCouchbaseDataModel * ) self.instance runQuery:query];
    
    return r;
    

}

+ (NSArray *) getDeviceUserGalleryDocumentsWithStartKey: (NSString *) startKey andLimit: (NSInteger) limit {
    return [self getUserGalleryDocumentsWithStartKey: startKey 
                                            andLimit: limit 
                                    andUserIdentifer:  [DeviceUser uniqueIdentifier]];
}


         
+ (NSArray *) getGalleryDocumentsWithStartKey: (NSString *) startKey andLimit: (NSInteger) limit {
    
    //Create view;
    CouchDatabase * database = [self.instance database];
    CouchDesignDocument* design = [database designDocumentWithName: @"design"];
    NSAssert(design, @"Couldn't find design document");

  //  NSArray * r =  [ (MapCouchbaseDataModel * ) self.instance getView:@"galleryDocuments"];
 
    CouchQuery * query = [design queryViewNamed: @"galleryDocuments"]; //asLiveQuery];
    query.descending = NO;
    //query.limit = 50;
    NSLog(@"%@", @"Limit to 50 docs");
    NSArray * r = [(MapCouchbaseDataModel * ) self.instance runQuery:query];
        
    return r;
}

+ (NSArray *) getDetailDocumentsWithStartKey: (NSString *) startKey andLimit: (NSInteger) limit  {
    CouchDatabase * database = [self.instance database];

    CouchDesignDocument* design = [database designDocumentWithName: @"design"];
    NSAssert(design, @"Couldn't find design document");

    [design saveChanges];
    
   // NSArray * r = [ (MapCouchbaseDataModel * ) self.instance getView:@"detailDocuments" ];
    
    CouchQuery * query = [design queryViewNamed: @"detailDocuments"]; //asLiveQuery];
    query.descending = NO;
    NSArray * r = [(MapCouchbaseDataModel * ) self.instance runQuery: query];
    
    for(int i=0; i<[r count]; i++){
        NSDictionary * d = [r objectAtIndex:i];
        UIImage * mediumImage = [UIImage imageNamed:@"IMG_0068.jpg"]; //TODO: remove spoof
        //getDocumentImageData
        [d setValue:mediumImage forKey:@"medium"];
    }
    return r;

}


- (NSArray *) getView: (NSString *) viewName {
    
    CouchDesignDocument* design = [database designDocumentWithName: @"design"];
    self.query = [design queryViewNamed: viewName]; //asLiveQuery];
    query.descending = YES;
    
    
    CouchQueryEnumerator * enumerator = [query rows];
    if(!enumerator){
        return [NSArray array];
    }
    CouchQueryRow * row;
    NSMutableArray * data = [NSMutableArray array];
    while( (row =[enumerator nextRow]) ){
        [data addObject: (NSDictionary *) row.value];
    }
    return data;

}


+ (NSArray *) getUserDocuments {
    return [self getGalleryDocumentsWithStartKey:nil andLimit:nil];
}

+ (NSArray *) getUserDocumentsWithOffset:(NSInteger)offset andLimit:(NSInteger)limit {
    NSLog(@"getUserDocumentsWithOffset just calling getUserDocuments");
    return [self.instance _getUserDocuments];
}

+ (void) addDocument: (NSDictionary *) document {
    //Add any additional properties
    
    // Save the document, asynchronously:
    CouchDocument* doc = [self.instance.database untitledDocument];
    RESTOperation* op = [doc putProperties:document];
    [op onCompletion: ^{
        if (op.error)
            NSAssert(false, @"ERROR");
           // AppDelegate needs to observer MapData for connection errors.
           // [self showErrorAlert: @"Couldn't save the new item" forOperation: op];
        // Re-run the query:
		//[self.dataSource.query start];
        [self.instance.query start];
	}];
    [op start];

}





// Display an error alert, without blocking.
// If 'fatal' is true, the app will quit when it's pressed.
- (void)showAlert: (NSString*)message error: (NSError*)error fatal: (BOOL)fatal {
    if (error) {
        message = [NSString stringWithFormat: @"%@\n\n%@", message, error.localizedDescription];
    }
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle: (fatal ? @"Fatal Error" : @"Error")
                                                    message: message
                                                   delegate: (fatal ? self : nil)
                                          cancelButtonTitle: (fatal ? @"Quit" : @"Sorry")
                                          otherButtonTitles: nil];
    [alert show];
}


- (void)updateSyncURL {
    
    NSInteger count = [self.database getDocumentCount];

    
    if (!self.database){
        NSLog(@"No Database in updateSyncURL");
        return;
    }
    NSURL* newRemoteURL = nil;
    NSString *syncpoint = [RHSettings couchRemoteSyncURL];
    if (syncpoint.length > 0)
        newRemoteURL = [NSURL URLWithString:syncpoint];
    
    [self forgetSync];
    
    NSLog(@"Setting up replication %@", [newRemoteURL debugDescription]);
    NSArray* repls = [self.database replicateWithURL: newRemoteURL exclusively: YES];
    _pull = [repls objectAtIndex: 0];
    _push = [repls objectAtIndex: 1];
    [_pull addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
    [_push addObserver: self forKeyPath: @"completed" options: 0 context: NULL];
}


- (void) forgetSync {
    [_pull removeObserver: self forKeyPath: @"completed"];
    _pull = nil;
    [_push removeObserver: self forKeyPath: @"completed"];
    _push = nil;
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object 
                         change:(NSDictionary *)change context:(void *)context
{
    if (object == _pull || object == _push) {
        unsigned completed = _pull.completed + _push.completed;
        unsigned total = _pull.total + _push.total;
        NSLog(@"SYNC progress: %u / %u", completed, total);
        if (total > 0 && completed < total) {
           // [self showSyncStatus];
           // [progress setProgress:(completed / (float)total)];
            database.server.activityPollInterval = 0.5;   // poll often while progress is showing
        } else {
           // [self showSyncButton];
            database.server.activityPollInterval = 2.0;   // poll less often at other times
        }
    }
}

@end
