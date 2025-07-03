namespace Microsoft.Integration.Shopify;

/// <summary>
/// Page Shpfy Order Shipping Charges (ID 30128).
/// </summary>
page 30128 "Shpfy Order Shipping Charges"
{
    Caption = 'Shopify Order Shipping Charges';
    DeleteAllowed = false;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    PageType = List;
    PromotedActionCategories = 'New,Process,Report,Inspect';
    SourceTable = "Shpfy Order Shipping Charges";
    UsageCategory = None;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field(ShopifyShippingLineId; Rec."Shopify Shipping Line Id")
                {
                    ApplicationArea = All;
                    Visible = false;
                    ToolTip = 'Specifies a unique identifier for the shipping.';
                }
                field(ShopifyOrderId; Rec."Shopify Order Id")
                {
                    ApplicationArea = All;
                    Visible = false;
                    ToolTip = 'Specifies a unique identifier for the order.';
                }
                field(Title; Rec.Title)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the delivery method in Shopify.';
                }
                field(Amount; Rec.Amount)
                {
                    ApplicationArea = All;
                    Caption = 'Amount';
                    ToolTip = 'Specifies the shipping cost amount.';
                }
                field(PresentmentAmount; Rec."Presentment Amount")
                {
                    ApplicationArea = All;
                    Caption = 'Presentment Amount';
                    ToolTip = 'Specifies the shipping cost amount in presentment currency.';
                    Visible = this.PresentmentCurrencyVisible;
                }
                field("Discount Amount"; Rec."Discount Amount")
                {
                    ApplicationArea = All;
                    Caption = 'Discount Amount';
                    ToolTip = 'Specifies the shipping cost discount amount.';
                }
                field("Presentment Discount Amount"; Rec."Presentment Discount Amount")
                {
                    ApplicationArea = All;
                    Caption = 'Presentment Discount Amount';
                    ToolTip = 'Specifies the shipping cost discount amount in presentment currency.';
                    Visible = this.PresentmentCurrencyVisible;
                }
                field(Source; Rec.Source)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the origin of the shipping cost.';
                }
            }
        }
        area(factboxes)
        {
            systempart(Links; Links)
            {
                ApplicationArea = All;
                Visible = false;
            }
            systempart(Notes; Notes)
            {
                ApplicationArea = All;
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(RetrievedShopifyData)
            {
                ApplicationArea = All;
                Caption = 'Retrieved Shopify Data';
                Image = Entry;
                Promoted = true;
                PromotedCategory = Category4;
                PromotedIsBig = true;
                PromotedOnly = true;
                ToolTip = 'View the data retrieved from Shopify.';

                trigger OnAction();
                var
                    DataCapture: Record "Shpfy Data Capture";
                begin
                    DataCapture.SetCurrentKey("Linked To Table", "Linked To Id");
                    DataCapture.SetRange("Linked To Table", Database::"Shpfy Order Shipping Charges");
                    DataCapture.SetRange("Linked To Id", Rec.SystemId);
                    Page.Run(Page::"Shpfy Data Capture List", DataCapture);
                end;
            }
        }
    }

    var
        PresentmentCurrencyVisible: Boolean;

    trigger OnAfterGetRecord()
    begin
        this.SetShowPresentmentCurrencyCode();
    end;

    local procedure SetShowPresentmentCurrencyCode()
    var
        OrderHeader: Record "Shpfy Order Header";
        Shop: Record "Shpfy Shop";
    begin
        if not OrderHeader.Get(Rec."Shopify Order Id") then
            exit;

        if OrderHeader.IsProcessed() then
            this.SetOrderCurrencyHandling(OrderHeader)
        else
            if Shop.Get(OrderHeader."Shop Code") then
                this.SetShopCurrencyHandling(Shop)
    end;

    local procedure SetOrderCurrencyHandling(OrderHeader: Record "Shpfy Order Header")
    begin
        case OrderHeader."Processed Currency Handling" of
            "Shpfy Currency Handling"::"Shop Currency":
                this.PresentmentCurrencyVisible := false;
            "Shpfy Currency Handling"::"Presentment Currency":
                this.PresentmentCurrencyVisible := true;
        end;
    end;

    local procedure SetShopCurrencyHandling(Shop: Record "Shpfy Shop")
    begin
        case Shop."Currency Handling" of
            "Shpfy Currency Handling"::"Shop Currency":
                this.PresentmentCurrencyVisible := false;
            "Shpfy Currency Handling"::"Presentment Currency":
                this.PresentmentCurrencyVisible := true;
        end;
    end;
}

