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
                field(Amount; this.Amount)
                {
                    ApplicationArea = All;
                    Caption = 'Amount';
                    ToolTip = 'Specifies the shipping cost amount.';
                }
                field("Discount Amount"; this.DiscountAmount)
                {
                    ApplicationArea = All;
                    Caption = 'Discount Amount';
                    ToolTip = 'Specifies the shipping cost discount amount.';
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
        Amount: Decimal;
        DiscountAmount: Decimal;

    trigger OnAfterGetRecord()
    begin
        this.SetCurrencyCode();
    end;

    local procedure SetCurrencyCode()
    var
        OrderHeader: Record "Shpfy Order Header";
        Shop: Record "Shpfy Shop";
    begin
        if not OrderHeader.Get(Rec."Shopify Order Id") then begin
            this.SetDefaultAmounts();
            exit;
        end;

        if not OrderHeader.IsProcessed() then
            this.SetOrderCurrencyHandling(OrderHeader)
        else
            if Shop.Get(OrderHeader."Shop Code") then
                this.SetShopCurrencyHandling(Shop)
            else
                this.SetDefaultAmounts();
    end;

    local procedure SetDefaultAmounts()
    begin
        this.DiscountAmount := Rec."Discount Amount";
        this.Amount := Rec.Amount;
    end;

    local procedure SetShopCurrencyAmounts()
    begin
        Rec."Discount Amount" := Rec."Discount Amount";
        this.Amount := Rec.Amount;
    end;

    local procedure SetPresentmentCurrencyAmounts()
    begin
        this.DiscountAmount := Rec."Presentment Discount Amount";
        this.Amount := Rec."Presentment Amount";
    end;

    local procedure SetOrderCurrencyHandling(var OrderHeader: Record "Shpfy Order Header")
    begin
        case OrderHeader."Processed w. Currency Handling" of
            "Shpfy Currency Handling"::"Shop Currency":
                this.SetShopCurrencyAmounts();
            "Shpfy Currency Handling"::"Presentment Currency":
                this.SetPresentmentCurrencyAmounts();
        end;
    end;

    local procedure SetShopCurrencyHandling(var Shop: Record "Shpfy Shop")
    begin
        case Shop."Currency Handling" of
            "Shpfy Currency Handling"::"Shop Currency":
                this.SetShopCurrencyAmounts();
            "Shpfy Currency Handling"::"Presentment Currency":
                this.SetPresentmentCurrencyAmounts();
        end;
    end;
}

