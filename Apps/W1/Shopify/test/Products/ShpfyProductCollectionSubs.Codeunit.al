codeunit 139545 "Shpfy Product Collection Subs."
{
    EventSubscriberInstance = Manual;

    var
        PublishProductGraphQueryTxt: Text;
        ProductCreateGraphQueryTxt: Text;
        JEdges: JsonArray;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Communication Events", OnClientSend, '', true, false)]
    local procedure OnClientSend(HttpRequestMessage: HttpRequestMessage; var HttpResponseMessage: HttpResponseMessage)
    begin
        this.MakeResponse(HttpRequestMessage, HttpResponseMessage);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Shpfy Communication Events", OnGetContent, '', true, false)]
    local procedure OnGetContent(HttpResponseMessage: HttpResponseMessage; var Response: Text)
    begin
        HttpResponseMessage.Content.ReadAs(Response);
    end;

    local procedure MakeResponse(HttpRequestMessage: HttpRequestMessage; var HttpResponseMessage: HttpResponseMessage)
    var
        GQLProductCollections: Codeunit "Shpfy GQL ProductCollections";
        Uri: Text;
        GraphQlQuery: Text;

        PublishProductTok: Label '{"query":"mutation {publishablePublish(id: \"gid://shopify/Product/', locked = true;
        ProductCreateTok: Label '{"query":"mutation {productCreate(', locked = true;
        VariantCreateTok: Label '{"query":"mutation { productVariantsBulkCreate(', locked = true;
        GraphQLCmdTxt: Label '/graphql.json', Locked = true;
    begin
        case HttpRequestMessage.Method of
            'POST':
                begin
                    Uri := HttpRequestMessage.GetRequestUri();
                    if Uri.EndsWith(GraphQLCmdTxt) then
                        if HttpRequestMessage.Content.ReadAs(GraphQlQuery) then
                            case true of
                                GraphQlQuery.Contains(PublishProductTok):
                                    begin
                                        HttpResponseMessage := this.GetEmptyPublishResponse();
                                        this.PublishProductGraphQueryTxt := GraphQlQuery;
                                    end;
                                GraphQlQuery.Contains(ProductCreateTok):
                                    begin
                                        HttpResponseMessage := this.GetCreateProductResponse();
                                        this.ProductCreateGraphQueryTxt := GraphQlQuery;
                                    end;
                                GraphQlQuery = GQLProductCollections.GetGraphQL():
                                    HttpResponseMessage := this.GetProductCollectionsResponse();
                                GraphQlQuery.Contains(VariantCreateTok):
                                    HttpResponseMessage := this.GetCreatedVariantResponse();
                            end;
                end;
        end;
    end;

    local procedure GetEmptyPublishResponse(): HttpResponseMessage;
    var
        HttpResponseMessage: HttpResponseMessage;
        BodyTxt: Text;
        ResInStream: InStream;
    begin
        NavApp.GetResource('Products/EmptyPublishResponse.txt', ResInStream, TextEncoding::UTF8);
        ResInStream.ReadText(BodyTxt);
        HttpResponseMessage.Content.WriteFrom(BodyTxt);
        exit(HttpResponseMessage);
    end;

    local procedure GetCreateProductResponse(): HttpResponseMessage
    var
        HttpResponseMessage: HttpResponseMessage;
        BodyTxt: Text;
        ResInStream: InStream;
    begin
        NavApp.GetResource('Products/CreatedProductResponse.txt', ResInStream, TextEncoding::UTF8);
        ResInStream.ReadText(BodyTxt);
        HttpResponseMessage.Content.WriteFrom(BodyTxt);
        exit(HttpResponseMessage);
    end;

    local procedure GetCreatedVariantResponse(): HttpResponseMessage;
    var
        Any: Codeunit Any;
        NewVariantId: BigInteger;
        HttpResponseMessage: HttpResponseMessage;
        BodyTxt: Text;
        ResInStream: InStream;
    begin
        Any.SetDefaultSeed();
        NewVariantId := Any.IntegerInRange(100000, 999999);
        NavApp.GetResource('Products/CreatedVariantResponse.txt', ResInStream, TextEncoding::UTF8);
        ResInStream.ReadText(BodyTxt);
        HttpResponseMessage.Content.WriteFrom(StrSubstNo(BodyTxt, NewVariantId));
        exit(HttpResponseMessage);
    end;

    local procedure GetProductCollectionsResponse(): HttpResponseMessage
    var
        HttpResponseMessage: HttpResponseMessage;
        BodyTxt: Text;
        EdgesTxt: Text;
    begin
        this.JEdges.WriteTo(EdgesTxt);
        BodyTxt := StrSubstNo('{ "data": { "collections": { "edges": %1 } }}', EdgesTxt);
        HttpResponseMessage.Content.WriteFrom(BodyTxt);
        exit(HttpResponseMessage);
    end;

    internal procedure GetPublishProductGraphQueryTxt(): Text
    begin
        exit(this.PublishProductGraphQueryTxt);
    end;

    internal procedure GetProductCreateGraphQueryTxt(): Text
    begin
        exit(this.ProductCreateGraphQueryTxt);
    end;

    internal procedure SetJEdges(NewJEdges: JsonArray)
    begin
        this.JEdges := NewJEdges;
    end;
}