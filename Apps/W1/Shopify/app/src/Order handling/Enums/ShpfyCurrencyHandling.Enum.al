namespace Microsoft.Integration.Shopify;

/// <summary>
/// Enum Shpfy Currency Handling (ID 30168).
/// </summary>
enum 30168 "Shpfy Currency Handling"
{
    Extensible = false;
    Caption = 'Shopify Currency Handling';

    value(0; "Shop Currency")
    {
        Caption = 'Shop Currency';
    }
    value(1; "Presentment Currency")
    {
        Caption = 'Presentment Currency';
    }
}
