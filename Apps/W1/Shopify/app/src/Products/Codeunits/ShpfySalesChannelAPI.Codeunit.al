namespace Microsoft.Integration.Shopify;

/// <summary>
/// Codeunit Shpfy Sales Channel API (ID 30215).
/// </summary>
codeunit 30215 "Shpfy Sales Channel API"
{
    Access = Internal;

    var
        JsonHelper: Codeunit "Shpfy Json Helper";
        CommunicationMgt: Codeunit "Shpfy Communication Mgt.";

    /// <summary>
    /// Retrieves the sales channels from Shopify and updates the table with the new sales channels.
    /// </summary>
    /// <param name="ShopCode">The code of the shop.</param>
    internal procedure RetrieveSalesChannelsFromShopify(ShopCode: Code[20])
    var
        GraphQLType: Enum "Shpfy GraphQL Type";
        JResponse: JsonToken;
        JPublications: JsonArray;
    begin
        CommunicationMgt.SetShop(ShopCode);
        JResponse := CommunicationMgt.ExecuteGraphQL(GraphQLType::GetSalesChannels);
        if JsonHelper.GetJsonArray(JResponse, JPublications, 'data.publications.edges') then
            ProcessPublications(JPublications, ShopCode);
    end;

    /// <summary>
    /// Processes the sales channels from Shopify.
    /// </summary>
    /// <param name="JPublications">The array of sales channels data from Shopify.</param>
    /// <param name="ShopCode">The code of the shop.</param>
    internal procedure ProcessPublications(JPublications: JsonArray; ShopCode: Code[20])
    var
        CurrentChannels: List of [BigInteger];
    begin
        CurrentChannels := CollectChannels(ShopCode);
        InsertNewChannels(JPublications, ShopCode, CurrentChannels);
        RemoveNotExistingChannels(CurrentChannels);
    end;

    local procedure CollectChannels(ShopCode: Code[20]): List of [BigInteger]
    var
        SalesChannel: Record "Shpfy Sales Channel";
        Channels: List of [BigInteger];
    begin
        SalesChannel.SetRange("Shop Code", ShopCode);
        if SalesChannel.FindSet() then
            repeat
                Channels.Add(SalesChannel.Id);
            until SalesChannel.Next() = 0;
        exit(Channels);
    end;

    local procedure RemoveNotExistingChannels(CurrentChannels: List of [BigInteger])
    var
        SalesChannel: Record "Shpfy Sales Channel";
        ChannelId: BigInteger;
    begin
        foreach ChannelId in CurrentChannels do begin
            SalesChannel.Get(ChannelId);
            SalesChannel.Delete(true);
        end;
    end;

    local procedure InsertNewChannels(JPublications: JsonArray; ShopCode: Code[20]; CurrentChannels: List of [BigInteger])
    var
        SalesChannel: Record "Shpfy Sales Channel";
        JPublication: JsonToken;
        ChannelId: BigInteger;
        JCatalogEdges: JsonArray;
        JCatalogEdge: JsonToken;
        Handle: Text;
    begin
        foreach JPublication in JPublications do begin
            ChannelId := CommunicationMgt.GetIdOfGId(JsonHelper.GetValueAsText(JPublication, '$.node.id'));
            if not SalesChannel.Get(ChannelId) then begin
                SalesChannel.Init();
                SalesChannel.Validate(Id, ChannelId);
                JCatalogEdges := JsonHelper.GetJsonArray(JPublication, '$.node.catalog.apps.edges');
                JCatalogEdges.Get(0, JCatalogEdge);
                SalesChannel.Validate(Name, JsonHelper.GetValueAsText(JCatalogEdge, '$.node.title'));
                Handle := JsonHelper.GetValueAsText(JCatalogEdge, '$.node.handle');
                if Handle = 'online_store' then
                    SalesChannel.Default := true;
                SalesChannel."Shop Code" := ShopCode;
                SalesChannel.Insert(true);
            end else
                CurrentChannels.Remove(ChannelId);
        end;
    end;
}