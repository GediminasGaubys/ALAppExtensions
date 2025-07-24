namespace Microsoft.Integration.Shopify;

/// <summary>
/// Codeunit Shpfy GQL Product Collections (ID 30400) implements Interface Shpfy IGraphQL.
/// </summary>
codeunit 30400 "Shpfy GQL ProductCollections" implements "Shpfy IGraphQL"
{
    Access = Internal;

    /// <summary>
    /// GetGraphQL.
    /// </summary>
    /// <returns>Return value of type Text.</returns>
    internal procedure GetGraphQL(): Text
    begin
        exit('{"query": "{collections(first:25, query:\"collection_type:custom\") { pageInfo{hasNextPage} edges{ cursor node{ id title } } } }"}');
    end;

    /// <summary>
    /// GetExpectedCost.
    /// </summary>
    /// <returns>Return value of type Integer.</returns>
    internal procedure GetExpectedCost(): Integer
    begin
        exit(22);
    end;
}
