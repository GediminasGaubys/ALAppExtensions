namespace Microsoft.Integration.Shopify;

page 30169 "Shpfy Refund Shipping Lines"
{
    Caption = 'Refund Shipping Lines';
    PageType = List;
    SourceTable = "Shpfy Refund Shipping Line";
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(General)
            {
                field(Title; Rec.Title)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the title of the refund shipping line.';
                }
                field("Subtotal Amount"; Rec."Subtotal Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the subtotal price of a refund shipping line.';
                }
                field("Presentment Subtotal Amount"; Rec."Presentment Subtotal Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the subtotal price of a refund shipping line in the presentment currency.';
                    Visible = this.PresentmentCurrencyVisible;
                }
                field("Tax Amount"; Rec."Tax Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the total tax amount of a refund shipping line.';
                }
                field("Presentment Tax Amount"; Rec."Presentment Tax Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the total tax amount of a refund shipping line in the presentment currency.';
                    Visible = this.PresentmentCurrencyVisible;
                }
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
                ToolTip = 'View the data retrieved from Shopify.';

                trigger OnAction();
                var
                    DataCapture: Record "Shpfy Data Capture";
                begin
                    DataCapture.SetCurrentKey("Linked To Table", "Linked To Id");
                    DataCapture.SetRange("Linked To Table", Database::"Shpfy Refund Shipping Line");
                    DataCapture.SetRange("Linked To Id", Rec.SystemId);
                    Page.Run(Page::"Shpfy Data Capture List", DataCapture);
                end;
            }
        }
        area(Promoted)
        {
            actionref(PromotedRetrievedShopifyData; RetrievedShopifyData) { }
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
        RefundHeader: Record "Shpfy Refund Header";
        Shop: Record "Shpfy Shop";
    begin
        if not RefundHeader.Get(Rec."Refund Id") then
            exit;

        if not OrderHeader.Get(RefundHeader."Order Id") then
            exit;

        if not OrderHeader.IsProcessed() then
            this.SetOrderCurrencyHandling(OrderHeader)
        else
            if Shop.Get(OrderHeader."Shop Code") then
                this.SetShopCurrencyHandling(Shop)
    end;

    local procedure SetOrderCurrencyHandling(OrderHeader: Record "Shpfy Order Header")
    begin
        case OrderHeader."Processed w. Currency Handling" of
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