namespace Microsoft.Integration.Shopify;

/// <summary>
/// Codeunit Shpfy GQL Get Next Custom Product Collections (ID 30401) implements Interface Shpfy IGraphQL.
/// </summary>
codeunit 30401 "Shpfy GQL NextCustProdColls" implements "Shpfy IGraphQL"
{
    Access = Internal;

    /// <summary>
    /// GetGraphQL.
    /// </summary>
    /// <returns>Return value of type Text.</returns>
    internal procedure GetGraphQL(): Text
    begin
        exit('{"query": "{collections(first:25, after:\"{{After}}\", query:\"collection_type:custom\") { pageInfo{hasNextPage} edges{ cursor node{ id title } } } }"}');
    end;

    /// <summary>
    /// GetExpectedCost.
    /// </summary>
    /// <returns>Return value of type Integer.</returns>
    internal procedure GetExpectedCost(): Integer
    begin
        exit(32);
    end;
}
