unit databaseinfra;

//{$mode ObjFPC}{$H+}

{$I mormot.defines.inc}
{$I globaldefines.inc}

interface

uses
  Classes,
  SysUtils,
  servicesshared,
  productserviceinterface,
  documentserviceinterface,
  productdom,
  documentdom,
  restapiclient;

type
  TSharedmORMotDDD = class(TObject)
  private
    FConnected         : boolean;
    fDS                : IDocumentService;
    fPS                : IProductService;
    fRestApi           : TRestApiConnector;
    fUseRestApi        : boolean;
    DataBaseConnection : TObject;
    DataBaseServer     : TObject;
  public
    constructor Create;
    destructor Destroy;override;

    procedure ConnectNew(remote:boolean; ownserver:boolean);
    procedure ConnectRestApi(const aHost: RawUTF8; const aPort: RawUTF8);
    procedure DisConnect;

    function  GetProductTable(var Products:TProductCollection):boolean;

    function  GetProduct(var Product: TProduct):boolean;
    function  AddProduct(const Product: TProduct):boolean;
    function  UpdateProductCode(const Product: TProduct; const NewCode:RawUTF8):boolean;
    function  UpdateProduct(const Product: TProduct; const FieldInfo:RawUTF8):boolean;overload; // FieldInfo can only be a single fieldname or all fields "*"
    function  DeleteProduct(const Product: TProduct):boolean;
    function  ChangedProduct(const Product: TProduct;out Changed:boolean):boolean;

    function  GetDocuments(const Product: TProduct; var ADocuments: TDocumentCollection):boolean;
    function  GetDocument(const AProductDocument: TProductDocument; var ADocument: TDocument):boolean;
    function  GetDocumentThumb(const AProductDocument: TProductDocument):boolean;
    function  AddDocument(var AProductDocument: TProductDocument):boolean;

  published
    property Connected         : boolean read FConnected;
    property DocumentService   : IDocumentService read fDS;
    property ProductService    : IProductService read fPS;
    property RestApiConnector  : TRestApiConnector read fRestApi;
    property UsingRestApi      : boolean read fUseRestApi;
  end;


implementation

uses
  server,
  client,
  mormot.core.base,
  mormot.core.json,
  mormot.core.variants;

constructor TSharedmORMotDDD.Create;
begin
  DataBaseConnection := nil;
  DataBaseServer := nil;
  fRestApi := nil;
  fUseRestApi := false;
  inherited Create;
end;

destructor TSharedmORMotDDD.Destroy;
begin
  DisConnect;
  inherited Destroy;
end;

procedure TSharedmORMotDDD.ConnectNew(remote:boolean; ownserver:boolean);
begin
  if (NOT fConnected) then
  begin
    fConnected:=True;

    if remote then
    begin
      try
        if ownserver then
        begin
          DataBaseServer := TServer.Create({HTTPServer=}true);
        end;
        try
          DataBaseConnection:=TClient.Create('localhost');
          with DataBaseConnection AS TClient do
          begin
            if (ClientConnected) then
            begin
              fPS:=ClientProductService;
              fDS:=ClientDocumentService;
            end;
          end;
        except
          fConnected:=False;
        end;
      except
        fConnected:=False;
      end;
    end
    else
    begin
      try
        DataBaseConnection:=TServer.Create(ownserver);
        with DataBaseConnection AS TServer do
        begin
          fPS:=ServerProductService;
          fDS:=ServerDocumentService;
        end;
      except
        fConnected:=False;
      end;
    end;
  end;

  if fConnected then
  begin
    fConnected:=(Assigned(fPS) AND Assigned(fDS));
  end;

  if (NOT fConnected) then DisConnect;
end;

procedure TSharedmORMotDDD.ConnectRestApi(const aHost: RawUTF8; const aPort: RawUTF8);
begin
  if (NOT fConnected) then
  begin
    fUseRestApi := true;
    try
      fRestApi := TRestApiConnector.Create(aHost, aPort);
      fConnected := fRestApi.Connect;
    except
      fConnected := false;
    end;

    if (NOT fConnected) then DisConnect;
  end;
end;

procedure TSharedmORMotDDD.DisConnect;
begin
  fDS:=nil;
  fPS:=nil;

  if Assigned(fRestApi) then
  begin
    fRestApi.Free;
    fRestApi:=nil;
  end;
  fUseRestApi := false;

  if Assigned(DataBaseConnection) then
  begin
    DataBaseConnection.Destroy;
    DataBaseConnection:=nil;
  end;

  if Assigned(DataBaseServer) then
  begin
    DataBaseServer.Destroy;
    DataBaseServer:=nil;
  end;

  fConnected:=false;
end;

function TSharedmORMotDDD.GetProductTable(var Products:TProductCollection):boolean;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if Assigned(Products) then
  begin
    if fUseRestApi then
      result := fRestApi.GetAllProducts(Products)
    else
      result:=(ProductService.GetAllProducts(Products) = seSuccess);
  end;
end;

function TSharedmORMotDDD.GetProduct(var Product: TProduct):boolean;
var
  FetchedProduct: TProduct;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    if fRestApi.GetProductByCode(Product.ProductCode, FetchedProduct) then
    begin
      Product.Brand := FetchedProduct.Brand;
      Product.Model := FetchedProduct.Model;
      Product.Thumb := FetchedProduct.Thumb;
      Product.Version := FetchedProduct.Version;
      FetchedProduct.Free;
      result := true;
    end;
  end
  else
    result:=(ProductService.GetProduct(Product) = seSuccess);
end;

function TSharedmORMotDDD.AddProduct(const Product: TProduct):boolean;
var
  Response: RawUtf8;
  Body: RawUtf8;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    // POST product data as JSON to the REST API
    Body := JsonEncode(['ProductCode', Product.ProductCode,
                        'Brand', Product.Brand,
                        'Model', Product.Model]);
    result := (fRestApi.Post('/root/ProductService.AddProduct', Body, Response) = 200);
  end
  else
    result:=(ProductService.AddProduct(Product) = seSuccess);
end;

function TSharedmORMotDDD.UpdateProductCode(const Product: TProduct; const NewCode:RawUTF8):boolean;
var
  Response: RawUtf8;
  Body: RawUtf8;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    Body := JsonEncode(['aProductCode', Product.Code, 'NewCode', NewCode]);
    result := (fRestApi.Post('/root/ProductService.UpdateProductCode', Body, Response) = 200);
  end
  else
    result:=(ProductService.UpdateProductCode(Product.Code,NewCode) = seSuccess);
end;

function TSharedmORMotDDD.UpdateProduct(const Product: TProduct; const FieldInfo:RawUTF8):boolean;
var
  TD           : variant;
  Response: RawUtf8;
  Body: RawUtf8;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    if ProductFieldsToVariant(Product,FieldInfo,TD) then
    begin
      Body := JsonEncode(['aProductCode', Product.Code, 'FieldData', TD]);
      result := (fRestApi.Post('/root/ProductService.UpdateProduct', Body, Response) = 200);
    end;
  end
  else
  begin
    if ProductFieldsToVariant(Product,FieldInfo,TD) then
      result:=(ProductService.UpdateProduct(Product.Code,TD) = seSuccess);
  end;
end;

function TSharedmORMotDDD.DeleteProduct(const Product: TProduct):boolean;
var
  Response: RawUtf8;
  Body: RawUtf8;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    Body := JsonEncode(['aProductCode', Product.ProductCode]);
    result := (fRestApi.Post('/root/ProductService.DeleteProduct', Body, Response) = 200);
  end
  else
    result:=(ProductService.DeleteProduct(Product.ProductCode) = seSuccess);
end;

function TSharedmORMotDDD.ChangedProduct(const Product: TProduct; out Changed:boolean):boolean;
var
  Response: RawUtf8;
  Body: RawUtf8;
  Doc: TDocVariantData;
begin
  result:=false;
  Changed:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
  begin
    Body := JsonEncode(['aProductCode', Product.ProductCode,
                        'aVersion', Product.Version]);
    if (fRestApi.Post('/root/ProductService.ChangedProduct', Body, Response) = 200) then
    begin
      Doc.InitJson(Response, JSON_FAST);
      if Doc.GetValueIndex('Changed') >= 0 then
        Changed := Doc.B['Changed'];
      result := true;
    end;
  end
  else
    result:=(ProductService.ChangedProduct(Product.ProductCode,Product.Version,Changed) = seSuccess);
end;

function TSharedmORMotDDD.GetDocuments(const Product: TProduct; var ADocuments: TDocumentCollection):boolean;
var
  ProductDocumentRunner: TProductDocument;
  ADocument:TDocument;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
    exit; // Document retrieval not yet supported via REST API
  if Assigned(ADocuments) then
  begin
    for TCollectionItem(ProductDocumentRunner) in Product.Documents do
    begin
      // Find the document or create a new one if not existing
      ADocuments.AddOrUpdate(ProductDocumentRunner.Hash,true,ADocument);
      // Get the document if any
      result:=(DocumentService.FindDocument(ProductDocumentRunner.Hash,ADocument) = seSuccess);
    end;
  end;
end;

function TSharedmORMotDDD.GetDocument(const AProductDocument: TProductDocument; var ADocument: TDocument):boolean;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
    exit; // Document retrieval not yet supported via REST API
  if Assigned(ADocument) then
  begin
    // Get the document if any
    result:=(DocumentService.FindDocument(AProductDocument.Hash,ADocument) = seSuccess);
  end;
end;

function TSharedmORMotDDD.GetDocumentThumb(const AProductDocument: TProductDocument):boolean;
var
  Document:TDocument;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
    exit; // Document thumb retrieval not yet supported via REST API
  if Assigned(AProductDocument) then
  begin
    Document:=TDocument.Create(nil);
    Document.Hash:=AProductDocument.Hash;
    // Get the document thumb if any
    result:=(DocumentService.GetDocumentThumb(Document) = seSuccess);
    if result then
    begin
      AProductDocument.FileThumb:=Document.FileThumb;
    end;
    Document.Free;
  end;
end;

function TSharedmORMotDDD.AddDocument(var AProductDocument: TProductDocument):boolean;
var
  Document       : TDocument;
  LocalProduct   : TProduct;
begin
  result:=false;
  if (NOT fConnected) then exit;
  if fUseRestApi then
    exit; // Document upload not yet supported via REST API
  if Assigned(AProductDocument) then
  begin
    LocalProduct:=AProductDocument.GetOwner;
    Document:=TDocument.Create(nil);
    try
      Document.SetData(AProductDocument.Path,True);
      Document.ProductCode:=LocalProduct.ProductCode;
      Document.Hash:=AProductDocument.Hash;
      result:=(DocumentService.AddDocument(Document) = seSuccess);
      if result then
      begin
        // We now have a thumb of the file
        // Save it in the ProductDocument for rapid GUI
        AProductDocument.FileThumb:=Document.FileThumb;
      end;
    finally
      Document.Free;
    end;
  end;
end;

end.

