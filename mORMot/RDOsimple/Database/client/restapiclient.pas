unit restapiclient;

{$mode objfpc}{$H+}

{$I mormot.defines.inc}
{$I globaldefines.inc}

interface

uses
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.core.json,
  mormot.core.buffers,
  mormot.core.variants,
  mormot.core.rtti,
  mormot.core.unicode,
  mormot.net.client,
  {$ifdef USE_JWT}
  mormot.crypt.jwt,
  {$endif}
  servicesshared,
  productdom,
  documentdom;

type
  /// HTTP method verbs for REST requests
  THttpMethod = (hmGET, hmPOST, hmPUT, hmDELETE);

  /// A standalone REST API connector that communicates with the ProductData
  /// server using plain HTTP requests to its REST endpoints, without
  /// depending on mORMot's SOA service resolution framework.
  TRestApiConnector = class(TObject)
  strict private
    fBaseUrl: RawUtf8;
    fPort: RawUtf8;
    fConnected: boolean;
    {$ifdef USE_JWT}
    fJwtToken: RawUtf8;
    {$endif}
    function BuildUrl(const aPath: RawUtf8): RawUtf8;
  public
    constructor Create(const aHost: RawUtf8; const aPort: RawUtf8);
    destructor Destroy; override;

    /// Attempt to connect and verify the server is reachable
    function Connect: boolean;

    /// Execute an HTTP request and return the status code
    function Request(aMethod: THttpMethod; const aPath: RawUtf8;
      const aBody: RawUtf8; out aResponse: RawUtf8): integer;

    // Convenience methods for common HTTP verbs
    function Get(const aPath: RawUtf8; out aResponse: RawUtf8): integer;
    function Post(const aPath: RawUtf8; const aBody: RawUtf8; out aResponse: RawUtf8): integer;
    function Put(const aPath: RawUtf8; const aBody: RawUtf8; out aResponse: RawUtf8): integer;
    function Delete(const aPath: RawUtf8; out aResponse: RawUtf8): integer;

    /// Fetch all products from the REST API as a TProductCollection
    function GetAllProducts(var AProducts: TProductCollection): boolean;

    /// Fetch a single product by its code
    function GetProductByCode(const aCode: RawUtf8; out AProduct: TProduct): boolean;

    /// Fetch a product image by its code
    function GetProductImageByCode(const aCode: RawUtf8; out AImage: RawBlob): boolean;

    /// Fetch server info / timestamp
    function GetServerInfo(out aInfo: RawUtf8): boolean;

    property Connected: boolean read fConnected;
    property BaseUrl: RawUtf8 read fBaseUrl;
    property Port: RawUtf8 read fPort;
  end;

implementation

const
  HTTP_METHOD_TEXT: array[THttpMethod] of RawUtf8 = (
    'GET', 'POST', 'PUT', 'DELETE'
  );

{$ifdef USE_JWT}
function GenerateRestJwtToken(const UserName: RawUtf8 = ''): RawUtf8;
var
  Jwt: TJwtHS256;
begin
  Jwt := TJwtHS256.Create(SECRET_KEY, 10,
    [jrcIssuer, jrcExpirationTime, jrcIssuedAt, jrcJWTID], [], 60);
  try
    if Length(UserName) = 0 then
      Result := Jwt.Compute([], 'RestApiClient')
    else
      Result := Jwt.Compute([], UserName);
  finally
    Jwt.Free;
  end;
end;
{$endif}

{ TRestApiConnector }

constructor TRestApiConnector.Create(const aHost: RawUtf8; const aPort: RawUtf8);
begin
  inherited Create;
  fBaseUrl := aHost;
  fPort := aPort;
  fConnected := false;
  {$ifdef USE_JWT}
  fJwtToken := GenerateRestJwtToken;
  {$endif}
end;

destructor TRestApiConnector.Destroy;
begin
  fConnected := false;
  inherited Destroy;
end;

function TRestApiConnector.BuildUrl(const aPath: RawUtf8): RawUtf8;
begin
  Result := 'http://' + fBaseUrl + ':' + fPort + aPath;
end;

function TRestApiConnector.Connect: boolean;
var
  Response: RawUtf8;
  Status: integer;
begin
  Result := false;
  try
    Status := Get('/info', Response);
    fConnected := (Status = 200);
    Result := fConnected;
  except
    fConnected := false;
  end;
end;

function TRestApiConnector.Request(aMethod: THttpMethod; const aPath: RawUtf8;
  const aBody: RawUtf8; out aResponse: RawUtf8): integer;
var
  Client: TSimpleHttpClient;
  Url: RawUtf8;
  Header: RawUtf8;
begin
  Result := 0;
  aResponse := '';
  Client := TSimpleHttpClient.Create;
  try
    Client.TimeOut := 10000; // 10 second timeout
    Url := BuildUrl(aPath);
    Header := '';
    {$ifdef USE_JWT}
    Header := 'Authorization: Bearer ' + fJwtToken + #13#10;
    {$endif}
    aResponse := Client.Request(Url, HTTP_METHOD_TEXT[aMethod], Header, aBody);
    Result := Client.Status;
  finally
    Client.Free;
  end;
end;

function TRestApiConnector.Get(const aPath: RawUtf8; out aResponse: RawUtf8): integer;
begin
  Result := Request(hmGET, aPath, '', aResponse);
end;

function TRestApiConnector.Post(const aPath: RawUtf8; const aBody: RawUtf8;
  out aResponse: RawUtf8): integer;
begin
  Result := Request(hmPOST, aPath, aBody, aResponse);
end;

function TRestApiConnector.Put(const aPath: RawUtf8; const aBody: RawUtf8;
  out aResponse: RawUtf8): integer;
begin
  Result := Request(hmPUT, aPath, aBody, aResponse);
end;

function TRestApiConnector.Delete(const aPath: RawUtf8; out aResponse: RawUtf8): integer;
begin
  Result := Request(hmDELETE, aPath, '', aResponse);
end;

function TRestApiConnector.GetAllProducts(var AProducts: TProductCollection): boolean;
var
  Response: RawUtf8;
  Status: integer;
  Doc: TDocVariantData;
  ProductsArray: PDocVariantData;
  ProductObj: PDocVariantData;
  LocalProduct: TProduct;
  i: integer;
begin
  Result := false;
  if not Assigned(AProducts) then
    exit;

  Status := Get('/products', Response);
  if Status <> 200 then
    exit;

  // The /products endpoint returns JSON via ProductService.GetAllProducts
  // which wraps the result in {"AProducts": [...]}
  Doc.InitJson(Response, JSON_FAST);
  if Doc.Kind = dvObject then
  begin
    ProductsArray := Doc.A['AProducts'];
    if ProductsArray <> nil then
    begin
      for i := 0 to ProductsArray^.Count - 1 do
      begin
        ProductObj := _Safe(ProductsArray^.Values[i]);
        if ProductObj <> nil then
        begin
          if AProducts.AddOrUpdate(
            ProductObj^.U['ProductCode'], true, LocalProduct) then
          begin
            LocalProduct.Brand := ProductObj^.U['Brand'];
            LocalProduct.Model := ProductObj^.U['Model'];
            if ProductObj^.GetValueIndex('Version') >= 0 then
              LocalProduct.Version := ProductObj^.I['Version'];
            // Decode the Thumb if present (Base64-encoded)
            if ProductObj^.GetValueIndex('Thumb') >= 0 then
              LocalProduct.Thumb := Base64ToBin(ProductObj^.U['Thumb']);
          end;
        end;
      end;
      Result := true;
    end;
  end;
end;

function TRestApiConnector.GetProductByCode(const aCode: RawUtf8;
  out AProduct: TProduct): boolean;
var
  Response: RawUtf8;
  Status: integer;
  Doc: TDocVariantData;
  ProductObj: PDocVariantData;
begin
  Result := false;
  AProduct := nil;

  Status := Get('/product/' + aCode, Response);
  if Status <> 200 then
    exit;

  // The endpoint returns JSON with the product data wrapped in {"AProduct": {...}}
  Doc.InitJson(Response, JSON_FAST);
  if Doc.Kind = dvObject then
  begin
    ProductObj := Doc.O['AProduct'];
    if ProductObj <> nil then
    begin
      AProduct := TProduct.Create(nil);
      AProduct.ProductCode := ProductObj^.U['ProductCode'];
      AProduct.Brand := ProductObj^.U['Brand'];
      AProduct.Model := ProductObj^.U['Model'];
      if ProductObj^.GetValueIndex('Version') >= 0 then
        AProduct.Version := ProductObj^.I['Version'];
      if ProductObj^.GetValueIndex('Thumb') >= 0 then
        AProduct.Thumb := Base64ToBin(ProductObj^.U['Thumb']);
      Result := true;
    end;
  end;
end;

function TRestApiConnector.GetProductImageByCode(const aCode: RawUtf8;
  out AImage: RawBlob): boolean;
var
  Response: RawUtf8;
  Status: integer;
begin
  Result := false;
  AImage := '';

  Status := Get('/product/' + aCode + '/image', Response);
  if Status <> 200 then
    exit;

  // The image endpoint returns the raw bitmap after server-side AfterRequest processing
  AImage := Response;
  Result := Length(AImage) > 0;
end;

function TRestApiConnector.GetServerInfo(out aInfo: RawUtf8): boolean;
var
  Status: integer;
begin
  Status := Get('/info', aInfo);
  Result := (Status = 200);
end;

end.
