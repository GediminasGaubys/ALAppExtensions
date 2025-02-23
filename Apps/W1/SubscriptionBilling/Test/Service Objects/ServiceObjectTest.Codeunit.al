namespace Microsoft.SubscriptionBilling;

using Microsoft.Foundation.Attachment;
using Microsoft.Foundation.Calendar;
using Microsoft.Finance.Currency;
using System.TestLibraries.Utilities;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Item.Attribute;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Pricing;
using Microsoft.CRM.Contact;
using Microsoft.Pricing.Calculation;
using Microsoft.Pricing.Source;
using Microsoft.Pricing.Asset;
using Microsoft.Pricing.PriceList;

codeunit 148157 "Service Object Test"
{
    Subtype = Test;
    Access = Internal;

    var
        Assert: Codeunit Assert;
        ContractTestLibrary: Codeunit "Contract Test Library";
        LibraryERMCountryData: Codeunit "Library - ERM Country Data";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryPriceCalculation: Codeunit "Library - Price Calculation";
        LibraryRandom: Codeunit "Library - Random";
        LibrarySales: Codeunit "Library - Sales";
        LibraryTestInitialize: Codeunit "Library - Test Initialize";
        LibraryVariableStorage: Codeunit "Library - Variable Storage";
        NoStartDateErr: Label 'Start Date is not entered.', Locked = true;
        IsInitialized: Boolean;

    #region Tests

    [Test]
    procedure CheckArchivedServCommAmounts()
    var
        Item: Record Item;
        ServComm: Record "Service Commitment";
        TempServComm: Record "Service Commitment" temporary;
        ServCommArchive: Record "Service Commitment Archive";
        ServiceObject: Record "Service Object";
        OldQuantity: Decimal;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, true);
        // FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        // Save Service Commitments before changing quantity
        ServComm.SetRange("Service Object No.", ServiceObject."No.");
        ServComm.FindSet();
        repeat
            TempServComm := ServComm;
            TempServComm.Insert(false);
        until ServComm.Next() = 0;

        // Change quantity to create entries in Service Commitment Archive
        OldQuantity := ServiceObject."Quantity Decimal";
        ServiceObject.Validate("Quantity Decimal", LibraryRandom.RandDecInRange(2, 10, 2));
        ServiceObject.Modify(false);

        // Check if archive has saved the correct (old) Service Amount
        ServCommArchive.SetRange("Service Object No.", ServiceObject."No.");
        ServCommArchive.SetRange("Quantity Decimal (Service Ob.)", OldQuantity);
        ServCommArchive.FindSet();
        repeat
            TempServComm.Get(ServCommArchive."Original Entry No.");
            Assert.AreEqual(TempServComm."Service Amount", ServCommArchive."Service Amount", 'Service Amount in Service Commitment Archive should be the value of the Service Commitment before the quantity change.');
        until ServCommArchive.Next() = 0;
    end;

    [Test]
    procedure CheckArchivedServCommVariantCode()
    var
        Customer: Record Customer;
        Item: Record Item;
        ItemVariant: Record "Item Variant";
        ServiceCommitmentArchive: Record "Service Commitment Archive";
        ServiceObject: Record "Service Object";
        PreviousVariantCode: Code[10];
    begin
        // [SCENARIO] Create Service Object with the Service Commitment, create Item Variant and create Sales Price
        // [SCENARIO] Change the Variant Code in Service Object and check the value in Service Commitment Archive
        // [SCENARIO] Variant Code in Service Commitment Archive should be the value of the Service Object before the Variant Code change
        Initialize();

        // [GIVEN] Setup
        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, true, true);
        // FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        LibrarySales.CreateCustomer(Customer);
        LibraryInventory.CreateItemVariant(ItemVariant, Item."No.");
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Validate("Variant Code", ItemVariant.Code);
        ServiceObject.Modify(true);

        // [WHEN] Change the Variant Code to create entries in Service Commitment Archive
        PreviousVariantCode := ServiceObject."Variant Code";
        LibraryInventory.CreateItemVariant(ItemVariant, Item."No.");
        ServiceObject.Validate("Variant Code", ItemVariant.Code);
        ServiceObject.Modify(false);

        // Check if archive has saved the correct (old) Variant Code
        ServiceCommitmentArchive.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitmentArchive.SetRange("Variant Code (Service Object)", PreviousVariantCode);
        Assert.RecordIsNotEmpty(ServiceCommitmentArchive);
    end;

    [Test]
    procedure CheckCalculationBaseAmountAssignment()
    var
        Customer: Record Customer;
        Item: Record Item;
        PriceListLine: Record "Price List Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        EndingDate: Date;
        FutureReferenceDate: Date;
        CustomerPrice: array[4] of Decimal;
    begin
        Initialize();

        // Create Service Object and Service Commitments - Unit Price from Item should be taken as Calculation Base Amount
        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price");
        ServiceCommitmentPackage.SetRange(Code, ServiceCommitment."Package Code");
        ServiceCommitment.DeleteAll(false);

        // Assign End-User Customer No. Service Object with and create Service Commitments - Unit Price from Item should be taken as Calculation Base Amount
        ContractTestLibrary.CreateCustomer(Customer);
        ServiceObject.SetHideValidationDialog(true);
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);
        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price");
        ServiceCommitment.DeleteAll(false);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(false);

        // Create different Sales Prices for Customer
        CustomerPrice[1] := LibraryRandom.RandDec(100, 2); // normal price
        CustomerPrice[2] := Round(CustomerPrice[1] * 0.9, 2); // discounted price for Qty = 10
        CustomerPrice[3] := LibraryRandom.RandDecInRange(101, 200, 2); // price used in future
        CustomerPrice[4] := Round(CustomerPrice[3] * 0.9, 2); // price used in future + discounted price for Qty = 10
        FutureReferenceDate := CalcDate('<1M>', WorkDate());
        EndingDate := CalcDate('<-1D>', FutureReferenceDate);
        CreateCustomerSalesPrice(Item, Customer, WorkDate(), 0, CustomerPrice[1], EndingDate);
        CreateCustomerSalesPrice(Item, Customer, WorkDate(), 10, CustomerPrice[2], EndingDate);
        CreateCustomerSalesPrice(Item, Customer, FutureReferenceDate, 0, CustomerPrice[3], PriceListLine);
        CreateCustomerSalesPrice(Item, Customer, FutureReferenceDate, 10, CustomerPrice[4], PriceListLine);
        // test - normal price
        TestCalculationBaseAmount(1, WorkDate(), CustomerPrice[1], ServiceObject, ServiceCommitmentPackage);
        // test - discounted price for Qty = 10
        TestCalculationBaseAmount(10, WorkDate(), CustomerPrice[2], ServiceObject, ServiceCommitmentPackage);
        // test - price used in future
        TestCalculationBaseAmount(1, FutureReferenceDate, CustomerPrice[3], ServiceObject, ServiceCommitmentPackage);
        // test - price used in future + discounted price for Qty = 10
        TestCalculationBaseAmount(10, FutureReferenceDate, CustomerPrice[4], ServiceObject, ServiceCommitmentPackage);
    end;

    [Test]
    procedure CheckCalculationBaseAmountAssignmentForCustomerWithBillToCustomer()
    var
        Customer: Record Customer;
        Customer2: Record Customer;
        Item: Record Item;
        PriceListLine: Record "Price List Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        EndingDate: Date;
        FutureReferenceDate: Date;
        Customer2Price: array[4] of Decimal;
        CustomerPrice: array[4] of Decimal;
    begin
        Initialize();

        // Create Service Object and Service Commitments - Unit Price from Item should be taken as Calculation Base Amount
        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price");
        ServiceCommitmentPackage.SetRange(Code, ServiceCommitment."Package Code");
        ServiceCommitment.DeleteAll(false);

        // Create Customer and Customer2 and assign Customer2 as "Bill-to Customer No."" to Customer
        ContractTestLibrary.CreateCustomer(Customer);
        ContractTestLibrary.CreateCustomer(Customer2);
        Customer.Validate("Bill-to Customer No.", Customer2."No.");
        Customer.Modify(false);

        // Assign End-User Customer No. to Service Object and create Service Commitments - Unit Price from Item should be taken as Calculation Base Amount
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);
        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price");
        ServiceCommitment.DeleteAll(false);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(false);

        // Create different Sales Prices for Customer
        CustomerPrice[1] := LibraryRandom.RandDec(100, 2); // normal price
        CustomerPrice[2] := Round(CustomerPrice[1] * 0.9, 2); // discounted price for Qty = 10
        CustomerPrice[3] := LibraryRandom.RandDecInRange(101, 200, 2); // price used in future
        CustomerPrice[4] := Round(CustomerPrice[3] * 0.9, 2); // price used in future + discounted price for Qty = 10
        Customer2Price[1] := LibraryRandom.RandDec(100, 2); // normal price
        Customer2Price[2] := Round(Customer2Price[1] * 0.9, 2); // discounted price for Qty = 10
        Customer2Price[3] := LibraryRandom.RandDecInRange(101, 200, 2); // price used in future
        Customer2Price[4] := Round(Customer2Price[3] * 0.9, 2); // price used in future + discounted price for Qty = 10
        FutureReferenceDate := CalcDate('<1M>', WorkDate());
        EndingDate := CalcDate('<-1D>', FutureReferenceDate);
        CreateCustomerSalesPrice(Item, Customer2, WorkDate(), 0, Customer2Price[1], EndingDate);
        CreateCustomerSalesPrice(Item, Customer2, WorkDate(), 10, Customer2Price[2], EndingDate);
        CreateCustomerSalesPrice(Item, Customer2, FutureReferenceDate, 0, Customer2Price[3], PriceListLine);
        CreateCustomerSalesPrice(Item, Customer2, FutureReferenceDate, 10, Customer2Price[4], PriceListLine);
        CreateCustomerSalesPrice(Item, Customer, WorkDate(), 0, CustomerPrice[1], EndingDate);
        CreateCustomerSalesPrice(Item, Customer, WorkDate(), 10, CustomerPrice[2], EndingDate);
        CreateCustomerSalesPrice(Item, Customer, FutureReferenceDate, 0, CustomerPrice[3], PriceListLine);
        CreateCustomerSalesPrice(Item, Customer, FutureReferenceDate, 10, CustomerPrice[4], PriceListLine);

        // test - normal price
        TestCalculationBaseAmount(1, WorkDate(), Customer2Price[1], ServiceObject, ServiceCommitmentPackage);
        // test - discounted price for Qty = 10
        TestCalculationBaseAmount(10, WorkDate(), Customer2Price[2], ServiceObject, ServiceCommitmentPackage);
        // test - price used in future
        TestCalculationBaseAmount(1, FutureReferenceDate, Customer2Price[3], ServiceObject, ServiceCommitmentPackage);
        // test - price used in future + discounted price for Qty = 10
        TestCalculationBaseAmount(10, FutureReferenceDate, Customer2Price[4], ServiceObject, ServiceCommitmentPackage);
    end;

    [Test]
    procedure CheckCalculationDateFormulaEntry()
    var
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        Commit();  // retain data after asserterror

        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<5D>', '<20D>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1W>', '<4W>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1M>', '<6Q>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1Q>', '<3Q>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1Y>', '<2Y>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<3M>', '<1Y>');
        ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<6M>', '<1Q>');
        ServiceCommitment.Modify(true);

        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1D>', '<1M>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1W>', '<1M>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<2M>', '<7M>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<2Q>', '<5Q>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<2Y>', '<3Y>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<CM>', '<1Y>');
        asserterror ServiceCommitment.Modify(true);
        ContractTestLibrary.ValidateBillingBasePeriodAndBillingRhythmOnServiceCommitment(ServiceCommitment, '<1M + 1Q>', '<1Y>');
        asserterror ServiceCommitment.Modify(true);
    end;

    [Test]
    procedure CheckChangeQuantityIfCustomerPostingGroupEmpty()
    var
        CustomerWithPostingGroup: Record Customer;
        EndUserCustomer: Record Customer;
        Item: Record Item;
        ServiceObject: Record "Service Object";
        OldQuantity: Decimal;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);

        ContractTestLibrary.CreateCustomer(EndUserCustomer);
        ContractTestLibrary.CreateCustomer(CustomerWithPostingGroup);
        EndUserCustomer.Validate("Customer Posting Group", '');
        EndUserCustomer.Validate("Bill-to Customer No.", CustomerWithPostingGroup."No.");
        EndUserCustomer.Modify(false);

        ServiceObject.Validate("End-User Customer No.", EndUserCustomer."No.");
        ServiceObject.Modify(false);
        OldQuantity := ServiceObject."Quantity Decimal";
        ServiceObject.Validate("Quantity Decimal", ServiceObject."Quantity Decimal" + 1);
        Assert.AreEqual(OldQuantity + 1, ServiceObject."Quantity Decimal", 'Service Object Quantity has to be changeable with "Customer Posting Group" filled for "Bill-to Customer No.".');
    end;

    [Test]
    procedure CheckChangeServiceObjectSN()
    var
        Item: Record Item;
        ServCommArchive: Record "Service Commitment Archive";
        ServiceObject: Record "Service Object";
        SN: Code[50];
        ServiceObjectPage: TestPage "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, true, false);
        SN := ServiceObject."Serial No.";

        ServCommArchive.Reset();
        ServCommArchive.SetRange("Service Object No.", ServiceObject."No.");
        ServCommArchive.DeleteAll(false);

        ServiceObjectPage.OpenView();
        ServiceObjectPage.GoToRecord(ServiceObject);
        ServiceObjectPage."Serial No.".SetValue(LibraryRandom.RandText(MaxStrLen(ServiceObject."Serial No.")));
        ServiceObjectPage.Close();

        ServCommArchive.Reset();
        ServCommArchive.SetRange("Service Object No.", ServiceObject."No.");
        ServCommArchive.FindFirst();
        Assert.AreEqual(SN, ServCommArchive."Serial No. (Service Object)", 'The original Serial No. should have been archived.');
        Assert.RecordCount(ServCommArchive, 1);
    end;

    [Test]
    procedure CheckClearTerminationPeriods()
    var
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        ServiceCommitmentTemplateCode: Code[20];
        ServiceAndCalculationStartDate: Date;
        ServiceEndDate: Date;
    begin
        Initialize();

        ServiceAndCalculationStartDate := CalcDate('<-1Y>', WorkDate());
        SetupServiceObjectTemplatePackageAndAssignItemToPackage(ServiceCommitmentTemplateCode, ServiceObject, ServiceCommitmentPackage, ServiceCommPackageLine);
        ModifyCurrentServiceCommPackageLine('<12M>', '<12M>', '<1M>', ServiceCommPackageLine);

        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(ServiceAndCalculationStartDate, ServiceCommitmentPackage);

        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.FindFirst();
        Assert.AreEqual(0D, ServiceCommitment."Service End Date", '"Service End Date" is set.');
        Assert.AreNotEqual(0D, ServiceCommitment."Term Until", '"Term Until" not set.');
        Assert.AreNotEqual(0D, ServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" is not set.');

        ServiceEndDate := CalcDate('<-6M>', WorkDate());

        ServiceCommitment.Validate("Service End Date", ServiceEndDate);
        Assert.AreEqual(0D, ServiceCommitment."Term Until", '"Term Until" not cleared.');
        Assert.AreEqual(0D, ServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" is not cleared.');
    end;

    [Test]
    procedure CheckDeleteServiceObjectWithArchivedServComm()
    var
        Item: Record Item;
        ServComm: Record "Service Commitment";
        ServCommArchive: Record "Service Commitment Archive";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, true);
        // FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        // Change quantity to create entries in Service Commitment Archive
        ServiceObject.Validate("Quantity Decimal", LibraryRandom.RandDecInRange(2, 10, 2));
        ServiceObject.Modify(false);
        ServCommArchive.SetRange("Service Object No.", ServiceObject."No.");
        Assert.AreNotEqual(0, ServCommArchive.Count(), 'Entries in Service Commitment Archive should exist after changing quantity in Service Object.');

        // Delete Service Commitments & Service Objects to check if archive gets deleted
        ServComm.Reset();
        ServComm.SetRange("Service Object No.", ServiceObject."No.");
        ServComm.DeleteAll(false);

        ServiceObject.Delete(true);
        Assert.AreEqual(0, ServCommArchive.Count(), 'Entries in Service Commitment Archive should be deleted after deleting Service Object.');
    end;

    [Test]
    [HandlerFunctions('AssignServiceCommitmentsModalPageHandler')]

    procedure CheckInvoicingItemNoInServiceObjectWithServiceCommitmentItem()
    var
        Item: Record Item;
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
        ServiceObjectPage: TestPage "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateItemWithServiceCommitmentOption(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item");
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);

        ServiceCommitmentTemplate.Description += ' Temp';
        ServiceCommitmentTemplate."Calculation Base Type" := Enum::"Calculation Base Type"::"Document Price";
        ServiceCommitmentTemplate."Calculation Base %" := 10;
        Evaluate(ServiceCommitmentTemplate."Billing Base Period", '<12M>');
        ServiceCommitmentTemplate."Invoicing via" := Enum::"Invoicing Via"::Contract;
        ServiceCommitmentTemplate.Modify(false);

        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage.Code);

        Evaluate(ServiceCommPackageLine."Extension Term", '<1M>');
        Evaluate(ServiceCommPackageLine."Notice Period", '<1M>');
        Evaluate(ServiceCommPackageLine."Initial Term", '<1M>');
        ServiceCommPackageLine.Partner := Enum::"Service Partner"::Vendor;
        Evaluate(ServiceCommPackageLine."Billing Rhythm", '<12M>');
        Evaluate(ServiceCommPackageLine."Price Binding Period", '<1M>');
        ServiceCommPackageLine.Modify(false);

        ServiceObjectPage.OpenEdit();
        ServiceObjectPage.GoToRecord(ServiceObject);
        ServiceObjectPage.AssignServices.Invoke();

        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceCommitment.TestField("Invoicing Item No.", Item."No.");
    end;

    [Test]
    [HandlerFunctions('ServiceObjectAttributeValueEditorModalPageHandlerTestValues')]
    procedure CheckLoadServiceObjectAttributes()
    var
        Item: Record Item;
        ItemAttribute: array[2] of Record "Item Attribute";
        ItemAttributeValue: array[2] of Record "Item Attribute Value";
        ServiceObject: Record "Service Object";
        ServiceObjectTestPage: TestPage "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateItemWithServiceCommitmentOption(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item");
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ContractTestLibrary.CreateServiceObjectAttributeMappedToServiceObject(ServiceObject."No.", ItemAttribute[1], ItemAttributeValue[1], false);
        ContractTestLibrary.CreateServiceObjectAttributeMappedToServiceObject(ServiceObject."No.", ItemAttribute[2], ItemAttributeValue[2], true);

        LibraryVariableStorage.Enqueue(ItemAttribute[1].ID);
        LibraryVariableStorage.Enqueue(ItemAttribute[2].ID);
        LibraryVariableStorage.Enqueue(ItemAttributeValue[1].ID);
        LibraryVariableStorage.Enqueue(ItemAttributeValue[2].ID);
        ServiceObjectTestPage.OpenEdit();
        ServiceObjectTestPage.GoToRecord(ServiceObject);
        ServiceObjectTestPage.Attributes.Invoke(); // ServiceObjectAttributeValueEditorModalPageHandlerTestValues
    end;

    [Test]
    procedure CheckServiceCommitmentBaseAmountAssignment()
    var
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, true, true);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price");

        ServiceCommitment.Next();
        ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Cost");
    end;

    [Test]
    procedure CheckServiceCommitmentCalculationBaseAmountIsNotRecalculatedOnServiceObjectQuantityChange()
    var
        Currency: Record Currency;
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        ExpectedCalculationBaseAmount: Decimal;
        ExpectedServiceAmount: Decimal;
        Price: Decimal;
        Quantity2: Decimal;
    begin
        Initialize();

        // If Service Commitment field "Calculation Base Amount" is changed manually
        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Calculation Base Amount");
        ExpectedCalculationBaseAmount := LibraryRandom.RandDec(100, 2);
        ServiceCommitment.Validate("Calculation Base Amount", ExpectedCalculationBaseAmount);
        ServiceCommitment.Modify(false);

        Currency.InitRoundingPrecision();
        Price := Round(ExpectedCalculationBaseAmount * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ExpectedServiceAmount := Round(ServiceObject."Quantity Decimal" * Price, Currency."Amount Rounding Precision");
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);

        // [WHEN] Service Object Quantity is changed
        Quantity2 := LibraryRandom.RandDec(10, 2);
        while Quantity2 = ServiceObject."Quantity Decimal" do
            Quantity2 := LibraryRandom.RandDec(10, 2);
        Price := Round(ExpectedCalculationBaseAmount * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ExpectedServiceAmount := Round(Quantity2 * Price, Currency."Amount Rounding Precision");
        ServiceObject.Validate("Quantity Decimal", Quantity2);

        // [THEN] "Calculation Base Amount" field should not be recalculated
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceCommitment.TestField("Calculation Base Amount", ExpectedCalculationBaseAmount);
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);
    end;

    [Test]
    procedure CheckServiceCommitmentDiscountCalculation()
    var
        Currency: Record Currency;
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        DiscountAmount: Decimal;
        DiscountPercent: Decimal;
        ExpectedDiscountAmount: Decimal;
        ExpectedDiscountPercent: Decimal;
        ServiceAmountInt: Integer;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Discount %", 0);
        ServiceCommitment.TestField("Discount Amount", 0);
        Currency.InitRoundingPrecision();

        DiscountPercent := LibraryRandom.RandDec(50, 2);
        ExpectedDiscountAmount := Round(ServiceCommitment."Service Amount" * DiscountPercent / 100, Currency."Amount Rounding Precision");
        ServiceCommitment.Validate("Discount %", DiscountPercent);
        ServiceCommitment.TestField("Discount Amount", ExpectedDiscountAmount);

        Evaluate(ServiceAmountInt, Format(ServiceCommitment."Service Amount", 0, '<Integer>'));
        DiscountAmount := LibraryRandom.RandDec(ServiceAmountInt, 2);
        ExpectedDiscountPercent := Round(DiscountAmount / Round((ServiceCommitment.Price * ServiceObject."Quantity Decimal"), Currency."Amount Rounding Precision") * 100, 0.00001);
        ServiceCommitment.Validate("Discount Amount", DiscountAmount);
        ServiceCommitment.TestField("Discount %", ExpectedDiscountPercent);
    end;

    [Test]
    procedure CheckServiceCommitmentPriceCalculation()
    var
        Currency: Record Currency;
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        ExpectedPrice: Decimal;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, true, true);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        Currency.InitRoundingPrecision();
        ExpectedPrice := Round(Item."Unit Price" * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ServiceCommitment.TestField(Price, ExpectedPrice);

        ServiceCommitment.Next();
        ExpectedPrice := Round(Item."Unit Cost" * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ServiceCommitment.TestField(Price, ExpectedPrice);
    end;

    [Test]
    procedure CheckServiceCommitmentServiceAmountCalculation()
    var
        Currency: Record Currency;
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        ChangedCalculationBaseAmount: Decimal;
        DiscountPercent: Decimal;
        ExpectedServiceAmount: Decimal;
        MaxServiceAmount: Decimal;
        NegativeServiceAmount: Decimal;
        Price: Decimal;
        ServiceAmountBiggerThanPrice: Decimal;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        Currency.InitRoundingPrecision();
        Price := Round(Item."Unit Price" * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ExpectedServiceAmount := Round(ServiceObject."Quantity Decimal" * Price, Currency."Amount Rounding Precision");
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);

        ChangedCalculationBaseAmount := LibraryRandom.RandDec(1000, 2);
        ServiceCommitment.Validate("Calculation Base Amount", ChangedCalculationBaseAmount);

        ExpectedServiceAmount := Round((ServiceCommitment.Price * ServiceObject."Quantity Decimal"), Currency."Amount Rounding Precision");
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);

        DiscountPercent := LibraryRandom.RandDec(100, 2);
        ServiceCommitment.Validate("Discount %", DiscountPercent);

        ExpectedServiceAmount := Round((ServiceCommitment.Price * ServiceObject."Quantity Decimal") - (ServiceCommitment.Price * ServiceObject."Quantity Decimal" * DiscountPercent / 100), Currency."Amount Rounding Precision");
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);
        Commit(); // retain data after asserterror

        ServiceAmountBiggerThanPrice := Round(ServiceCommitment.Price * (ServiceObject."Quantity Decimal" + 1), Currency."Amount Rounding Precision");
        asserterror ServiceCommitment.Validate("Service Amount", ServiceAmountBiggerThanPrice);
        NegativeServiceAmount := -1 * LibraryRandom.RandDec(100, 2);
        asserterror ServiceCommitment.Validate("Service Amount", NegativeServiceAmount);
        MaxServiceAmount := Round((ServiceCommitment.Price * ServiceObject."Quantity Decimal"), Currency."Amount Rounding Precision");
        asserterror ServiceCommitment.Validate("Discount Amount", MaxServiceAmount + LibraryRandom.RandDec(100, 2));
    end;

    [Test]
    procedure CheckServiceCommitmentServiceDates()
    var
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);

        ValidateServiceDateCombination(WorkDate(), WorkDate(), WorkDate(), ServiceObject."No.");
        ValidateServiceDateCombination(WorkDate(), CalcDate('<+5D>', WorkDate()), CalcDate('<+3D>', WorkDate()), ServiceObject."No.");
        ValidateServiceDateCombination(WorkDate(), CalcDate('<+5D>', WorkDate()), CalcDate('<+6D>', WorkDate()), ServiceObject."No."); // allow setting the Service End Date one day before Next Billing Date
        asserterror ValidateServiceDateCombination(WorkDate(), CalcDate('<+5D>', WorkDate()), CalcDate('<-3D>', WorkDate()), ServiceObject."No.");
        asserterror ValidateServiceDateCombination(WorkDate(), CalcDate('<+4D>', WorkDate()), CalcDate('<+6D>', WorkDate()), ServiceObject."No."); // do not allow setting the Service End Date two or more days before Next Billing Date - because Service was invoiced up to Next Billing Date
    end;

    [Test]
    procedure CheckServiceCommitmentServiceInitialEndDateCalculation()
    var
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        DateFormulaVariable: DateFormula;
        ExpectedServiceEndDate: Date;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceCommitment.Validate("Service Start Date", WorkDate());

        Evaluate(DateFormulaVariable, '<1M>');

        Clear(ServiceCommitment."Extension Term");
        ServiceCommitment.Validate("Initial Term", DateFormulaVariable);
        ExpectedServiceEndDate := CalcDate(ServiceCommitment."Initial Term", ServiceCommitment."Service Start Date");
        ExpectedServiceEndDate := CalcDate('<-1D>', ExpectedServiceEndDate);
        ServiceCommitment.CalculateInitialServiceEndDate();
        ServiceCommitment.TestField("Service End Date", ExpectedServiceEndDate);

        Clear(ServiceCommitment."Service End Date");
        ServiceCommitment.Validate("Extension Term", DateFormulaVariable);
        ServiceCommitment.CalculateInitialServiceEndDate();
        ServiceCommitment.TestField("Service End Date", 0D);

        Clear(ServiceCommitment."Service End Date");
        Clear(ServiceCommitment."Extension Term");
        Clear(ServiceCommitment."Initial Term");
        ServiceCommitment.CalculateInitialServiceEndDate();
        ServiceCommitment.TestField("Service End Date", 0D);
    end;

    [Test]
    procedure CheckServiceCommitmentServiceInitialTerminationDatesCalculation()
    var
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        ServiceCommitmentTemplateCode: Code[20];
        ServiceAndCalculationStartDate: Date;
    begin
        Initialize();

        ServiceAndCalculationStartDate := WorkDate();
        SetupServiceObjectTemplatePackageAndAssignItemToPackage(ServiceCommitmentTemplateCode, ServiceObject, ServiceCommitmentPackage, ServiceCommPackageLine);
        ModifyCurrentServiceCommPackageLine('<12M>', '<1M>', '<1M>', ServiceCommPackageLine);

        AddNewServiceCommPackageLine('<12M>', '<1M>', '', ServiceCommitmentTemplateCode, ServiceCommitmentPackage.Code, ServiceCommPackageLine);
        AddNewServiceCommPackageLine('<12M>', '', '', ServiceCommitmentTemplateCode, ServiceCommitmentPackage.Code, ServiceCommPackageLine);
        AddNewServiceCommPackageLine('', '<1M>', '<1M>', ServiceCommitmentTemplateCode, ServiceCommitmentPackage.Code, ServiceCommPackageLine);
        AddNewServiceCommPackageLine('', '<1M>', '', ServiceCommitmentTemplateCode, ServiceCommitmentPackage.Code, ServiceCommPackageLine);
        AddNewServiceCommPackageLine('', '', '', ServiceCommitmentTemplateCode, ServiceCommitmentPackage.Code, ServiceCommPackageLine);

        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(ServiceAndCalculationStartDate, ServiceCommitmentPackage);

        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");

        ServiceCommitment.FindFirst();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
        ServiceCommitment.Next();
        TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate, ServiceCommitment);
    end;

    [Test]
    procedure CheckServiceCommitmentUpdateTerminationDatesCalculation()
    var
        Item: Record Item;
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitment2: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
        ServiceAndCalculationStartDate: Date;
    begin
        Initialize();

        ServiceAndCalculationStartDate := CalcDate('<-5Y>', WorkDate());
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        Evaluate(ServiceCommitmentTemplate."Billing Base Period", '<12M>');
        ServiceCommitmentTemplate.Modify(false);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage.Code);

        Evaluate(ServiceCommPackageLine."Initial Term", '<12M>');
        Evaluate(ServiceCommPackageLine."Extension Term", '<12M>');
        Evaluate(ServiceCommPackageLine."Notice Period", '<1M>');
        Evaluate(ServiceCommPackageLine."Billing Rhythm", '<1M>');
        ServiceCommPackageLine.Modify(false);

        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(ServiceAndCalculationStartDate, ServiceCommitmentPackage);

        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        repeat
            ServiceCommitment2 := ServiceCommitment;
            ServiceCommitment.UpdateTermUntilUsingExtensionTerm();
            ServiceCommitment.UpdateCancellationPossibleUntil();
            ServiceCommitment.Modify(false);
            TestServiceCommitmentUpdatedTerminationDates(ServiceCommitment2, ServiceCommitment, ServiceCommitment);
        until WorkDate() <= ServiceCommitment."Cancellation Possible Until";
    end;

    [Test]
    procedure CheckServiceObjectQtyRecalculation()
    var
        Currency: Record Currency;
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        ExpectedCalculationBaseAmount: Decimal;
        ExpectedServiceAmount: Decimal;
        Price: Decimal;
        Quantity2: Decimal;
        Quantity3: Decimal;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        Currency.InitRoundingPrecision();
        Price := Round(Item."Unit Price" * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ExpectedServiceAmount := Round(ServiceObject."Quantity Decimal" * Price, Currency."Amount Rounding Precision");
        ServiceCommitment.TestField("Calculation Base Amount");
        ExpectedCalculationBaseAmount := ServiceCommitment."Calculation Base Amount";
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);

        Quantity2 := LibraryRandom.RandDec(10, 2);
        while Quantity2 = ServiceObject."Quantity Decimal" do
            Quantity2 := LibraryRandom.RandDec(10, 2);
        Price := Round(Item."Unit Price" * ServiceCommitment."Calculation Base %" / 100, Currency."Unit-Amount Rounding Precision");
        ExpectedServiceAmount := Round(Quantity2 * Price, Currency."Amount Rounding Precision");
        ServiceObject.Validate("Quantity Decimal", Quantity2);

        ServiceCommitment.FindFirst();
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);
        ServiceCommitment.TestField("Calculation Base Amount", ExpectedCalculationBaseAmount);

        Commit(); // retain data after asserterror
        Quantity3 := LibraryRandom.RandDec(10, 2);
        while Quantity3 = Quantity2 do
            Quantity3 := LibraryRandom.RandDec(10, 2);
        ServiceObject.SetHideValidationDialog(false);
        asserterror ServiceObject.Validate("Quantity Decimal", Quantity3);
        ServiceObject.TestField("Quantity Decimal", Quantity2);
        ServiceCommitment.FindFirst();
        ServiceCommitment.TestField("Service Amount", ExpectedServiceAmount);
        ServiceCommitment.TestField("Calculation Base Amount", ExpectedCalculationBaseAmount);

        asserterror ServiceObject.Validate("Quantity Decimal", 0);
    end;

    [Test]
    [HandlerFunctions('AssignServiceCommitmentsModalPageHandler')]
    procedure CheckServiceObjectsServiceCommitmentAssignment()
    var
        Item: Record Item;
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
        ServiceObjectPage: TestPage "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);

        ServiceCommitmentTemplate.Description += ' Temp';
        ServiceCommitmentTemplate."Calculation Base Type" := Enum::"Calculation Base Type"::"Document Price";
        ServiceCommitmentTemplate."Calculation Base %" := 10;
        Evaluate(ServiceCommitmentTemplate."Billing Base Period", '<12M>');
        ServiceCommitmentTemplate."Invoicing via" := Enum::"Invoicing Via"::Contract;
        ServiceCommitmentTemplate.Modify(false);

        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage.Code);

        Evaluate(ServiceCommPackageLine."Extension Term", '<1M>');
        Evaluate(ServiceCommPackageLine."Notice Period", '<1M>');
        Evaluate(ServiceCommPackageLine."Initial Term", '<1M>');
        ServiceCommPackageLine.Partner := Enum::"Service Partner"::Vendor;
        Evaluate(ServiceCommPackageLine."Billing Rhythm", '<12M>');
        ServiceCommPackageLine.Modify(false);

        ServiceObjectPage.OpenEdit();
        ServiceObjectPage.GoToRecord(ServiceObject);
        ServiceObjectPage.AssignServices.Invoke();

        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        ServiceCommitment.TestField("Package Code", ServiceCommPackageLine."Package Code");
        ServiceCommitment.TestField(Template, ServiceCommPackageLine.Template);
        ServiceCommitment.TestField(Description, ServiceCommPackageLine.Description);
        ServiceCommitment.TestField("Service Start Date", WorkDate());
        ServiceCommitment.TestField("Extension Term", ServiceCommPackageLine."Extension Term");
        ServiceCommitment.TestField("Notice Period", ServiceCommPackageLine."Notice Period");
        ServiceCommitment.TestField("Initial Term", ServiceCommPackageLine."Initial Term");
        ServiceCommitment.TestField(Partner, ServiceCommPackageLine.Partner);
        ServiceCommitment.TestField("Calculation Base %", ServiceCommPackageLine."Calculation Base %");
        ServiceCommitment.TestField("Billing Base Period", ServiceCommPackageLine."Billing Base Period");
        ServiceCommitment.TestField("Invoicing via", ServiceCommPackageLine."Invoicing via");
        ServiceCommitment.TestField("Invoicing Item No.", ServiceCommPackageLine."Invoicing Item No.");
        ServiceCommitment.TestField("Billing Rhythm", ServiceCommPackageLine."Billing Rhythm");
        ServiceCommitment.TestField("Price (LCY)", ServiceCommitment.Price);
        ServiceCommitment.TestField("Service Amount (LCY)", ServiceCommitment."Service Amount");
        ServiceCommitment.TestField("Discount Amount (LCY)", ServiceCommitment."Discount Amount");
        ServiceCommitment.TestField("Currency Code", '');
        ServiceCommitment.TestField("Currency Factor", 0);
        ServiceCommitment.TestField("Currency Factor Date", 0D);
        ServiceCommitment.TestField(Discount, false);
        ServiceCommitment.TestField("Price Binding Period", ServiceCommPackageLine."Price Binding Period");
        ServiceCommitment.TestField("Next Price Update", CalcDate(ServiceCommPackageLine."Price Binding Period", ServiceCommitment."Service Start Date"));
    end;

    [Test]

    procedure CheckServiceObjectsServiceCommitmentStandardPackagesAssignment()
    var
        Item: Record Item;
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.CreateServiceObjectItem(Item, false);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage.Code);

        ItemServCommitmentPackage.Get(Item."No.", ServiceCommitmentPackage.Code);
        ItemServCommitmentPackage.Standard := true;
        ItemServCommitmentPackage.Modify(false);
        ContractTestLibrary.CreateServiceObject(ServiceObject, Item."No.");

        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.SetRange(Template, ServiceCommitmentTemplate.Code);
        Assert.RecordIsNotEmpty(ServiceCommitment);
    end;

    [Test]
    procedure CheckUpdatingProvisionEndDateOnAfterFinishContractLines()
    var
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        ServiceCommitmentTemplateCode: Code[20];
        i: Integer;
    begin
        Initialize();

        i := -1;
        SetupServiceObjectTemplatePackageAndAssignItemToPackage(ServiceCommitmentTemplateCode, ServiceObject, ServiceCommitmentPackage, ServiceCommPackageLine);
        ModifyCurrentServiceCommPackageLine('<12M>', '<12M>', '<1M>', ServiceCommPackageLine);

        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        if ServiceCommitment.FindSet() then
            repeat
                ServiceCommitment."Service Start Date" := CalcDate('<-2D>', Today());
                ServiceCommitment."Service End Date" := Today() + i;
                ServiceCommitment."Next Billing Date" := CalcDate('<+1D>', ServiceCommitment."Service End Date");
                ServiceCommitment.Modify(false);
                i -= 1;
            until ServiceCommitment.Next() = 0;
        ServiceObject.UpdateServicesDates();
        Assert.AreEqual(CalcDate('<-1D>', Today()), ServiceObject."Provision End Date", 'Provision End Date was not updated properly.');
    end;

    [Test]
    procedure CheckUpdatingTerminationDatesOnManualValidation()
    var
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceObject: Record "Service Object";
        DateTimeManagement: Codeunit "Date Time Management";
        NegativeDateFormula: DateFormula;
        ServiceCommitmentTemplateCode: Code[20];
        ServiceAndCalculationStartDate: Date;
        DateFormulaLbl: Label '-%1', Locked = true;
    begin
        Initialize();

        ServiceAndCalculationStartDate := WorkDate();
        SetupServiceObjectTemplatePackageAndAssignItemToPackage(ServiceCommitmentTemplateCode, ServiceObject, ServiceCommitmentPackage, ServiceCommPackageLine);
        ModifyCurrentServiceCommPackageLine('<12M>', '<12M>', '<1M>', ServiceCommPackageLine);

        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(ServiceAndCalculationStartDate, ServiceCommitmentPackage);

        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.FindFirst();
        Assert.AreNotEqual(0D, ServiceCommitment."Term Until", '"Term Until" is not set.');
        Assert.AreNotEqual(0D, ServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" is not set.');
        Assert.AreNotEqual('', ServiceCommitment."Notice Period", '"Notice Period" is not set.');

        ServiceCommitment.Validate("Cancellation Possible Until", CalcDate('<+5D>', ServiceCommitment."Cancellation Possible Until"));
        Assert.AreEqual(CalcDate(ServiceCommitment."Notice Period", ServiceCommitment."Cancellation Possible Until"), ServiceCommitment."Term Until", '"Term Until" Date is not calculated correctly.');

        if DateTimeManagement.IsLastDayOfMonth(CalcDate('<-7D>', ServiceCommitment."Term Until")) then
            ServiceCommitment.Validate("Term Until", CalcDate('<-8D>', ServiceCommitment."Term Until"))
        else
            ServiceCommitment.Validate("Term Until", CalcDate('<-7D>', ServiceCommitment."Term Until"));
        Evaluate(NegativeDateFormula, StrSubstNo(DateFormulaLbl, ServiceCommitment."Notice Period"));
        Assert.AreEqual(CalcDate(NegativeDateFormula, ServiceCommitment."Term Until"), ServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" Date is not calculated correctly.');
    end;

    [Test]
    procedure ExpectDocumentAttachmentsAreDeleted()
    var
        DocumentAttachment: Record "Document Attachment";
        ServiceObject: Record "Service Object";
        i: Integer;
        RandomNoOfAttachments: Integer;
    begin
        Initialize();

        // Service Object has Document Attachments created
        // [WHEN] Service Object is deleted
        // expect that Document Attachments are deleted
        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        ServiceObject.TestField("No.");
        RandomNoOfAttachments := LibraryRandom.RandInt(10);
        for i := 1 to RandomNoOfAttachments do
            ContractTestLibrary.InsertDocumentAttachment(Database::"Service Object", ServiceObject."No.");

        DocumentAttachment.SetRange("Table ID", Database::"Service Object");
        DocumentAttachment.SetRange("No.", ServiceObject."No.");
        Assert.AreEqual(RandomNoOfAttachments, DocumentAttachment.Count(), 'Actual number of Document Attachment(s) is incorrect.');

        ServiceObject.Delete(true);
        Assert.AreEqual(0, DocumentAttachment.Count(), 'Document Attachment(s) should be deleted.');
    end;

    [Test]
    procedure ExpectErrorForNegativeServiceCommitmentDateFormulaFields()
    var
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        NegativeDateFormula: DateFormula;
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        Commit(); // retain data after asserterror

        Evaluate(NegativeDateFormula, '<-1M>');
        asserterror ServiceCommitment.Validate("Billing Base Period", NegativeDateFormula);
        asserterror ServiceCommitment.Validate("Notice Period", NegativeDateFormula);
        asserterror ServiceCommitment.Validate("Initial Term", NegativeDateFormula);
        asserterror ServiceCommitment.Validate("Extension Term", NegativeDateFormula);
        asserterror ServiceCommitment.Validate("Billing Rhythm", NegativeDateFormula);
    end;

    [Test]
    procedure ExpectErrorOnChangeEndUserIfCustomerPostingGroupEmpty()
    var
        EndUserCustomer: Record Customer;
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        // FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ContractTestLibrary.CreateCustomer(EndUserCustomer);
        EndUserCustomer.Validate("Customer Posting Group", '');
        EndUserCustomer.Modify(false);

        asserterror ServiceObject.Validate("End-User Customer No.", EndUserCustomer."No.");
    end;

    [Test]
    procedure ExpectErrorOnChangeEndUserIfServiceObjectIsLinkedToContract()
    var
        Customer: Record Customer;
        Customer2: Record Customer;
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, false);
        // FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceObject.SetHideValidationDialog(false);
        ContractTestLibrary.CreateCustomer(Customer);
        ServiceObject."End-User Customer No." := Customer."No.";
        ServiceObject.Modify(false);
        ContractTestLibrary.CreateCustomer(Customer2);
        asserterror ServiceObject.Validate("End-User Customer No.", Customer2."No.");
    end;

    [Test]
    [HandlerFunctions('ServiceObjectAttributeValueEditorModalPageHandlerExpectErrorOnPrimary')]
    procedure ExpectErrorOnDuplicatePrimaryServiceObjectAttribute()
    var
        Item: Record Item;
        ItemAttribute: array[2] of Record "Item Attribute";
        ItemAttributeValue: array[2] of Record "Item Attribute Value";
        ServiceObject: Record "Service Object";
        ServiceObjectTestPage: TestPage "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateItemWithServiceCommitmentOption(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item");
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ContractTestLibrary.CreateServiceObjectAttributeMappedToServiceObject(ServiceObject."No.", ItemAttribute[1], ItemAttributeValue[1], false);
        ContractTestLibrary.CreateServiceObjectAttributeMappedToServiceObject(ServiceObject."No.", ItemAttribute[2], ItemAttributeValue[2], true);

        ServiceObjectTestPage.OpenEdit();
        ServiceObjectTestPage.GoToRecord(ServiceObject);
        ServiceObjectTestPage.Attributes.Invoke(); // ServiceObjectAttributeValueEditorModalPageHandlerExpectErrorOnPrimary
    end;

    [Test]
    procedure TestModifyCustomerAddress()
    var
        Customer: Record Customer;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        // Create Service Object with End-User
        ContractTestLibrary.CreateCustomer(Customer);
        ContractTestLibrary.InitContractsApp();
        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        ServiceObject.SetHideValidationDialog(true);
        ServiceObject.Validate("End-User Customer No.");

        // Change in address fields should be possible without error
        ServiceObject.Validate("End-User Address", LibraryRandom.RandText(MaxStrLen(ServiceObject."End-User Address")));
        ServiceObject.Validate("End-User Address 2", LibraryRandom.RandText(MaxStrLen(ServiceObject."End-User Address 2")));
        ServiceObject.Modify(false);
    end;

    [Test]
    [HandlerFunctions('AssignServiceCommitmentsModalPageHandler')]
    procedure TestPriceGroupFilterOnAssignServiceCommitments()
    var
        Customer: Record Customer;
        CustomerPriceGroup: Record "Customer Price Group";
        Item: Record Item;
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommPackageLine2: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentPackage2: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
        ServiceObjectPage: TestPage "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.SetupSalesServiceCommitmentItemAndAssignToServiceCommitmentPackage(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item", ServiceCommitmentPackage.Code);
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ServiceObject.SetHideValidationDialog(true);
        ServiceCommitmentPackage.FilterCodeOnPackageFilter(ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);

        LibrarySales.CreateCustomerPriceGroup(CustomerPriceGroup);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage2, ServiceCommPackageLine2);
        ServiceCommitmentPackage2."Price Group" := CustomerPriceGroup.Code;
        ServiceCommitmentPackage2.Modify(false);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage2.Code, true);

        ContractTestLibrary.CreateCustomer(Customer);
        Customer."Customer Price Group" := CustomerPriceGroup.Code;
        Customer.Modify(false);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(true);

        ServiceCommitment.Reset();
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.DeleteAll(false); // Remove all service commitments assigned on Validate Item No. in Service Object

        ServiceObjectPage.OpenEdit();
        ServiceObjectPage.GoToRecord(ServiceObject);
        ServiceObjectPage.AssignServices.Invoke();
        // ServiceObjectPage.Close();

        ServiceCommitment.Reset();
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.FindSet();
        repeat
            ServiceCommitment.TestField("Package Code", ServiceCommitmentPackage2.Code); // Expect only Service commitments from Package 1 because of the Customer Price group
        until ServiceCommitment.Next() = 0;
    end;

    [Test]
    procedure TestRecalculateServiceCommitmentsOnChangeBillToCustomer()
    var
        Customer: Record Customer;
        Customer2: Record Customer;
        Item: Record Item;
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        TempSalesHeader: Record "Sales Header" temporary;
        TempSalesLine: Record "Sales Line" temporary;
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommPackageLine1: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentPackage2: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
        ContractsItemManagement: Codeunit "Contracts Item Management";
        NewUnitPrice: Decimal;
    begin
        Initialize();

        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.CreateServiceCommitmentPackageLine(ServiceCommitmentPackage.Code, ServiceCommitmentTemplate.Code, ServiceCommPackageLine);
        ContractTestLibrary.UpdateServiceCommitmentPackageLine(
                ServiceCommPackageLine, Format(ServiceCommPackageLine."Billing Base Period"), ServiceCommPackageLine."Calculation Base %",
                Format(ServiceCommPackageLine."Billing Rhythm"), Format(ServiceCommPackageLine."Extension Term"), "Service Partner"::Vendor, ServiceCommPackageLine."Invoicing Item No.");
        ContractTestLibrary.SetupSalesServiceCommitmentItemAndAssignToServiceCommitmentPackage(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item", ServiceCommitmentPackage.Code);
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ServiceObject.SetHideValidationDialog(true);
        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);

        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage2, ServiceCommPackageLine1);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage2.Code, true);

        ContractTestLibrary.CreateCustomer(Customer);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(true);

        ContractTestLibrary.CreateCustomer(Customer2);
        NewUnitPrice := LibraryRandom.RandDec(1000, 2);
        CreatePriceListForCustomer(Customer2."No.", NewUnitPrice, Item."No.");
        ServiceObject.Validate("Bill-to Customer No.", Customer2."No.");
        ServiceObject.Modify(true);

        ContractsItemManagement.CreateTempSalesHeader(TempSalesHeader, TempSalesHeader."Document Type"::Order, ServiceObject."End-User Customer No.", ServiceObject."Bill-to Customer No.", WorkDate(), '');
        ContractsItemManagement.CreateTempSalesLine(TempSalesLine, TempSalesHeader, ServiceObject."Item No.", ServiceObject."Quantity Decimal", WorkDate());

        ServiceCommitment.Reset();
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.SetRange(Partner, "Service Partner"::Customer);
        ServiceCommitment.FindSet();
        repeat
            NewUnitPrice := ContractsItemManagement.CalculateUnitPrice(TempSalesHeader, TempSalesLine);
            ServiceCommitment.TestField("Calculation Base Amount", NewUnitPrice);
        until ServiceCommitment.Next() = 0;

        ServiceCommitment.SetRange(Partner, "Service Partner"::Vendor);
        ServiceCommitment.FindSet();
        repeat
            ServiceCommitment.TestField("Calculation Base Amount", Item."Last Direct Cost");
        until ServiceCommitment.Next() = 0;
    end;

    [Test]
    procedure TestRecalculateServiceCommitmentsOnChangeServiceObjectQuantity()
    var
        Item: Record Item;
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, true);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceObject.Validate("Quantity Decimal", LibraryRandom.RandDecInRange(11, 100, 2)); // In the library init value for Quantity is in the range from 0 to 10
        ServiceObject.Modify(true);

        ServiceCommitment.Reset();
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.SetRange(Partner, "Service Partner"::Customer);
        ServiceCommitment.FindSet();
        repeat
            ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Price")
        until ServiceCommitment.Next() = 0;

        ServiceCommitment.SetRange(Partner, "Service Partner"::Vendor);
        ServiceCommitment.FindSet();
        repeat
            ServiceCommitment.TestField("Calculation Base Amount", Item."Unit Cost")
        until ServiceCommitment.Next() = 0;
    end;

    [Test]
    procedure TestRecalculateServiceCommitmentsOnChangeVariantCode()
    var
        Customer: Record Customer;
        Item: Record Item;
        ItemVariant: array[2] of Record "Item Variant";
        ServiceCommitment: Record "Service Commitment";
        ServiceObject: Record "Service Object";
        CustomerPrice: array[2] of Decimal;
    begin
        // [SCENARIO] Create Service Object with the Service Commitment, Create Item Variants and create Sales Prices
        // [SCENARIO] Change the Variant Code in Service Object and check the value of Calculation Base Amount in Service Commitment
        // [SCENARIO] Calculation Base Amount should be recalculated based on value of Variant Code that has been set in Sales Price
        Initialize();

        // [GIVEN] New pricing enabled
        LibraryPriceCalculation.EnableExtendedPriceCalculation();
        LibraryPriceCalculation.SetupDefaultHandler("Price Calculation Handler"::"Business Central (Version 16.0)");
        // [GIVEN] Setup
        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, true, true);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        LibrarySales.CreateCustomer(Customer);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(true);
        CustomerPrice[1] := LibraryRandom.RandDec(100, 2);
        CustomerPrice[2] := LibraryRandom.RandDec(100, 2);
        LibraryInventory.CreateItemVariant(ItemVariant[1], Item."No.");
        LibraryInventory.CreateItemVariant(ItemVariant[2], Item."No.");
        CreateCustomerSalesPriceWithVariantCode(Item, Customer, WorkDate(), 0, CustomerPrice[1], (CalcDate('<1M>', WorkDate())), ItemVariant[1].Code);
        CreateCustomerSalesPriceWithVariantCode(Item, Customer, WorkDate(), 0, CustomerPrice[2], (CalcDate('<1M>', WorkDate())), ItemVariant[2].Code);

        // [WHEN] Change the Variant Code on Service Object
        ServiceObject.Validate("Variant Code", ItemVariant[1].Code);
        ServiceObject.Modify(false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        // [THEN] Calculation Base Amount on Service Commitment should be recalculated based on value related to changed Variant Code
        Assert.AreEqual(CustomerPrice[1], ServiceCommitment."Calculation Base Amount", 'Calculation Base Amount should be taken from Sales Price based on Variant Code');

        // [WHEN] Change the Variant Code on Service Object
        ServiceObject.Validate("Variant Code", ItemVariant[2].Code);
        ServiceObject.Modify(false);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");

        // [THEN] Calculation Base Amount on Service Commitment should be recalculated based on value related to changed Variant Code
        Assert.AreEqual(CustomerPrice[2], ServiceCommitment."Calculation Base Amount", 'Calculation Base Amount should be taken from Sales Price based on Variant Code');
    end;

    [Test]
    procedure TestRecreateServiceCommitmentsOnChangeEndUser()
    var
        Customer: Record Customer;
        CustomerPriceGroup: Record "Customer Price Group";
        Item: Record Item;
        ItemServCommitmentPackage: Record "Item Serv. Commitment Package";
        ServiceCommPackageLine: Record "Service Comm. Package Line";
        ServiceCommPackageLine1: Record "Service Comm. Package Line";
        ServiceCommitment: Record "Service Commitment";
        ServiceCommitmentPackage: Record "Service Commitment Package";
        ServiceCommitmentPackage2: Record "Service Commitment Package";
        ServiceCommitmentTemplate: Record "Service Commitment Template";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.SetupSalesServiceCommitmentItemAndAssignToServiceCommitmentPackage(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item", ServiceCommitmentPackage.Code);
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ServiceObject.SetHideValidationDialog(true);
        ServiceCommitmentPackage.SetFilter(Code, ItemServCommitmentPackage.GetPackageFilterForItem(ServiceObject."Item No."));
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(WorkDate(), ServiceCommitmentPackage);

        LibrarySales.CreateCustomerPriceGroup(CustomerPriceGroup);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplate.Code, ServiceCommitmentPackage2, ServiceCommPackageLine1);
        ServiceCommitmentPackage2."Price Group" := CustomerPriceGroup.Code;
        ServiceCommitmentPackage2.Modify(false);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage2.Code, true);

        ContractTestLibrary.CreateCustomer(Customer);
        Customer."Customer Price Group" := CustomerPriceGroup.Code;
        Customer.Modify(false);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(true);

        ServiceCommitment.Reset();
        ServiceCommitment.SetRange("Service Object No.", ServiceObject."No.");
        ServiceCommitment.FindSet();
        repeat
            ServiceCommitment.TestField("Package Code", ServiceCommitmentPackage2.Code);
        until ServiceCommitment.Next() = 0;
    end;

    [Test]
    procedure UT_CheckCannotDeleteServiceObjectWhileServiceCommitmentExist()
    var
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        SetupServiceObjectWithServiceCommitment(Item, ServiceObject, false, true);
        asserterror ServiceObject.Delete(true);
    end;

    [Test]
    procedure UT_CheckCreateServiceObject()
    var
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObject(ServiceObject, '');

        ServiceObject.TestField("No.");
        ServiceObject.TestField("Quantity Decimal");
        asserterror ServiceObject.Validate("Quantity Decimal", -1);
    end;

    [Test]
    procedure UT_CheckCreateServiceObjectWithCustomerPriceGroup()
    var
        Customer: Record Customer;
        CustomerPriceGroup: Record "Customer Price Group";
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        ServiceObject.TestField("Customer Price Group", '');
        ContractTestLibrary.CreateCustomer(Customer);
        LibrarySales.CreateCustomerPriceGroup(CustomerPriceGroup);
        Customer."Customer Price Group" := CustomerPriceGroup.Code;
        Customer.Modify(false);
        ServiceObject.SetHideValidationDialog(true);
        ServiceObject.Validate("End-User Customer No.", Customer."No.");
        ServiceObject.Modify(false);
        ServiceObject.TestField("Customer Price Group", Customer."Customer Price Group");
    end;

    [Test]
    procedure UT_CheckCreateServiceObjectWithItemNo()
    var
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ServiceObject.TestField("Item No.", Item."No.");
        ServiceObject.TestField(Description, Item.Description);
    end;

    [Test]
    procedure UT_CheckServiceObjectQtyCannotBeBlank()
    var
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        asserterror ServiceObject.Validate("Quantity Decimal", 0);
    end;

    [Test]
    procedure UT_CheckServiceObjectQtyForSerialNo()
    var
        Item: Record Item;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, true);

        ServiceObject.TestField("Quantity Decimal", 1);
        ServiceObject.Validate("Serial No.", 'S1');
        Commit(); // retain data after asserterror

        asserterror ServiceObject.Validate("Quantity Decimal", 2);
        ServiceObject.Validate("Serial No.", '');
        ServiceObject.Validate("Quantity Decimal", 2);
        asserterror ServiceObject.Validate("Serial No.", 'S2');
    end;

    [Test]
    procedure UT_CheckTransferDefaultsFromContactToServiceObject()
    var
        Contact: Record Contact;
        Customer: Record Customer;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateContactsWithCustomerAndGetContactPerson(Contact, Customer);
        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        ServiceObject.SetHideValidationDialog(true);
        ServiceObject.Validate("End-User Contact No.", Contact."No.");
        ServiceObject.TestField("End-User Customer No.", Customer."No.");
        ServiceObject.TestField("End-User Customer Name", Customer.Name);
    end;

    [Test]
    procedure UT_CheckTransferDefaultsFromCustomerToServiceObject()
    var
        Customer: Record Customer;
        Customer2: Record Customer;
        ServiceObject: Record "Service Object";
    begin
        Initialize();

        ContractTestLibrary.CreateCustomer(Customer);
        ContractTestLibrary.CreateCustomer(Customer2);
        ContractTestLibrary.CreateServiceObject(ServiceObject, '');
        ServiceObject.SetHideValidationDialog(true);

        ServiceObject.Validate("End-User Customer Name", Customer.Name);
        ServiceObject.TestField("End-User Customer No.", Customer."No.");
        ServiceObject.Validate("Bill-to Name", Customer2.Name);
        ServiceObject.TestField("Bill-to Customer No.", Customer2."No.");
    end;

    [Test]
    procedure UT_ExpectItemDescriptionWhenCreateServiceObjectWithoutEndUser()
    var
        Item: Record Item;
        ItemTranslation: Record "Item Translation";
        ServiceObject: Record "Service Object";
    begin
        // [SCENARIO] When Create Service Object Without End User and add Item with translation, Item Description in Service Object should not be translated
        Initialize();

        // [GIVEN] Create: Language, Service Commitment Item with translation defined
        ContractTestLibrary.CreateItemWithServiceCommitmentOption(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item");
        ContractTestLibrary.CreateItemTranslation(ItemTranslation, Item."No.", '');

        // [WHEN] Create Service Object without End User
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);

        // [THEN] Item Description should not be translated in Service Object
        Assert.AreEqual(Item.Description, ServiceObject.Description, 'Item description should not be translated in Service Object');
    end;

    [Test]
    procedure UT_ExpectTranslatedItemDescriptionBasedOnCustomerLanguageCodeWhenCreateServiceObjectWithEndUser()
    var
        Customer: Record Customer;
        Item: Record Item;
        ItemTranslation: Record "Item Translation";
        ServiceObject: Record "Service Object";
    begin
        // [SCENARIO] When Create Service Object With End User and add Item with translation defined that match Customer Language Code, Item Description in Service Object should be translated
        Initialize();

        // [GIVEN] Create: Language, Service Commitment Item with translation defined, Customer with Language Code, Service Object with End User
        ContractTestLibrary.CreateItemWithServiceCommitmentOption(Item, Enum::"Item Service Commitment Type"::"Service Commitment Item");
        ContractTestLibrary.CreateItemTranslation(ItemTranslation, Item."No.", '');
        LibrarySales.CreateCustomer(Customer);
        Customer."Language Code" := ItemTranslation."Language Code";
        Customer.Modify(false);
        MockServiceObjectWithEndUserCustomerNo(ServiceObject, Customer."No.");

        // [WHEN] add Item in Service Object
        ServiceObject.Validate("Item No.", Item."No.");
        ServiceObject.Modify(false);

        // [THEN] Item Description should be translated in Service Object
        Assert.AreEqual(ItemTranslation.Description, ServiceObject.Description, 'Item description should be translated in Service Object');
    end;

    #endregion Tests

    #region Procedures

    local procedure Initialize()
    begin
        LibraryTestInitialize.OnTestInitialize(Codeunit::"Service Object Test");
        LibraryVariableStorage.AssertEmpty();

        if IsInitialized then
            exit;

        ContractTestLibrary.InitContractsApp();
        LibraryTestInitialize.OnBeforeTestSuiteInitialize(Codeunit::"Service Object Test");
        LibraryERMCountryData.UpdatePurchasesPayablesSetup();
        LibraryERMCountryData.UpdateSalesReceivablesSetup();
        ContractTestLibrary.EnableNewPricingExperience();
        IsInitialized := true;
        LibraryTestInitialize.OnAfterTestSuiteInitialize(Codeunit::"Service Object Test");
    end;

    local procedure AddNewServiceCommPackageLine(InitialTermDateFormulaText: Text; ExtensionTermDateFormulaText: Text; NoticePeriodDateFormulaText: Text; ServiceCommitmentTemplateCode: Code[20]; ServiceCommitmentPackageCode: Code[20]; var ServiceCommPackageLine: Record "Service Comm. Package Line")
    begin
        ContractTestLibrary.CreateServiceCommitmentPackageLine(ServiceCommitmentPackageCode, ServiceCommitmentTemplateCode, ServiceCommPackageLine);
        ModifyCurrentServiceCommPackageLine(InitialTermDateFormulaText, ExtensionTermDateFormulaText, NoticePeriodDateFormulaText, ServiceCommPackageLine);
    end;

    local procedure CreateCustomerSalesPrice(SourceItem: Record Item; SourceCustomer: Record Customer; StartingDate: Date; Quantity: Decimal; CustomerPrice: Decimal; var PriceListLine: Record "Price List Line")
    var
        PriceListHeader: Record "Price List Header";
    begin
        LibraryPriceCalculation.CreatePriceHeader(PriceListHeader, "Price Type"::Sale, "Price Source Type"::Customer, SourceCustomer."No.");
        PriceListHeader.Status := "Price Status"::Active;
        PriceListHeader."Allow Updating Defaults" := true;
        PriceListHeader."Currency Code" := '';
        PriceListHeader.Modify(true);

        LibraryPriceCalculation.CreatePriceListLine(PriceListLine, PriceListHeader, "Price Amount Type"::Price, "Price Asset Type"::Item, SourceItem."No.");
        PriceListLine.Validate("Starting Date", StartingDate);
        PriceListLine.Validate("Minimum Quantity", Quantity);
        PriceListLine."Currency Code" := '';
        PriceListLine.Validate("Unit Price", CustomerPrice);
        PriceListLine.Status := "Price Status"::Active;
        PriceListLine.Modify(true);
    end;

    local procedure CreateCustomerSalesPrice(SourceItem: Record Item; SourceCustomer: Record Customer; StartingDate: Date; Quantity: Decimal; CustomerPrice: Decimal; EndingDate: Date)
    var
        PriceListLine: Record "Price List Line";
    begin
        CreateCustomerSalesPrice(SourceItem, SourceCustomer, StartingDate, Quantity, CustomerPrice, PriceListLine);
        PriceListLine.Status := "Price Status"::Draft;
        PriceListLine.Validate("Ending Date", EndingDate);
        PriceListLine.Status := "Price Status"::Active;
        PriceListLine.Modify(true);
    end;

    local procedure CreateCustomerSalesPriceWithVariantCode(SourceItem: Record Item; SourceCustomer: Record Customer; StartingDate: Date; Quantity: Decimal; CustomerPrice: Decimal; EndingDate: Date; VariantCode: Code[10])
    begin
        CreateCustomerSalesPriceWithVariantCode(SourceItem, SourceCustomer, StartingDate, EndingDate, Quantity, CustomerPrice, VariantCode);
    end;

    local procedure CreateCustomerSalesPriceWithVariantCode(SourceItem: Record Item; SourceCustomer: Record Customer; StartingDate: Date; EndingDate: Date; Quantity: Decimal; CustomerPrice: Decimal; VariantCode: Code[10])
    var
        PriceListHeader: Record "Price List Header";
        PriceListLine: Record "Price List Line";
    begin
        LibraryPriceCalculation.CreatePriceHeader(PriceListHeader, "Price Type"::Sale, "Price Source Type"::Customer, SourceCustomer."No.");
        PriceListHeader.Status := "Price Status"::Active;
        PriceListHeader."Allow Updating Defaults" := true;
        PriceListHeader."Currency Code" := '';
        PriceListHeader.Modify(true);

        LibraryPriceCalculation.CreatePriceListLine(PriceListLine, PriceListHeader, "Price Amount Type"::Price, "Price Asset Type"::Item, SourceItem."No.");
        PriceListLine.Validate("Starting Date", StartingDate);
        PriceListLine.Validate("Ending Date", EndingDate);

        PriceListLine."Asset Type" := PriceListLine."Asset Type"::Item;
        PriceListLine."Product No." := SourceItem."No.";

        PriceListLine."Currency Code" := '';
        PriceListLine.Validate("Variant Code", VariantCode);
        PriceListLine.Validate("Unit Price", CustomerPrice);
        PriceListLine.Validate("Minimum Quantity", Quantity);
        PriceListLine.Status := "Price Status"::Active;
        PriceListLine.Modify(true);
    end;

    local procedure CreatePriceListForCustomer(CustomerNo: Code[20]; NewUnitPrice: Decimal; ItemNo: Code[20])
    var
        PriceListHeader: Record "Price List Header";
        PriceListLine: Record "Price List Line";
    begin
        LibraryPriceCalculation.CreatePriceHeader(PriceListHeader, "Price Type"::Sale, "Price Source Type"::Customer, CustomerNo);
        PriceListHeader.Status := "Price Status"::Active;
        PriceListHeader."Currency Code" := '';
        PriceListHeader.Modify(true);
        LibraryPriceCalculation.CreatePriceListLine(PriceListLine, PriceListHeader, "Price Amount Type"::Price, "Price Asset Type"::Item, ItemNo);
        PriceListLine.Validate("Unit Price", NewUnitPrice);
        PriceListLine.Modify(true);
    end;

    local procedure FindServiceCommitment(var ServiceCommitmentLine: Record "Service Commitment"; ServiceObjectNo: Code[20])
    begin
        ServiceCommitmentLine.SetRange("Service Object No.", ServiceObjectNo);
        ServiceCommitmentLine.FindFirst();
    end;

    local procedure GetCancellationPossibleUntilDate(StartDate: Date; InitialTermDateFormula: DateFormula; ExtensionTermDateFormula: DateFormula; NoticePeriodDateFormula: DateFormula) CancellationPossibleUntil: Date
    var
        NegativeDateFormula: DateFormula;
        DateFormulaLbl: Label '-%1', Locked = true;
    begin
        if Format(ExtensionTermDateFormula) = '' then
            exit;
        if Format(NoticePeriodDateFormula) = '' then
            exit;
        if Format(InitialTermDateFormula) = '' then
            exit;

        if StartDate = 0D then
            Error(NoStartDateErr);
        CancellationPossibleUntil := CalcDate(InitialTermDateFormula, StartDate);
        Evaluate(NegativeDateFormula, StrSubstNo(DateFormulaLbl, NoticePeriodDateFormula));
        CancellationPossibleUntil := CalcDate(NegativeDateFormula, CancellationPossibleUntil);
        CancellationPossibleUntil := CalcDate('<-1D>', CancellationPossibleUntil);
    end;

    local procedure GetTermUntilDate(StartDate: Date; EndDate: Date; InitialTermDateFormula: DateFormula; ExtensionTermDateFormula: DateFormula; NoticePeriodDateFormula: DateFormula) TermUntil: Date
    begin
        if EndDate <> 0D then begin
            TermUntil := EndDate;
            exit;
        end;

        if Format(ExtensionTermDateFormula) = '' then
            exit;
        if (Format(NoticePeriodDateFormula) = '') and (Format(InitialTermDateFormula) = '') then
            exit;

        if StartDate = 0D then
            Error(NoStartDateErr);
        if Format(InitialTermDateFormula) <> '' then begin
            TermUntil := CalcDate(InitialTermDateFormula, StartDate);
            TermUntil := CalcDate('<-1D>', TermUntil);
        end else begin
            TermUntil := CalcDate(NoticePeriodDateFormula, StartDate);
            TermUntil := CalcDate('<-1D>', TermUntil);
        end;
    end;

    local procedure GetUpdatedCancellationPossibleUntilDate(CalculationStartDate: Date; SourceServiceCommitment: Record "Service Commitment") CancellationPossibleUntil: Date
    var
        CalendarManagement: Codeunit "Calendar Management";
        DateTimeManagement: Codeunit "Date Time Management";
        NegativeDateFormula: DateFormula;
    begin
        if SourceServiceCommitment.IsNoticePeriodEmpty() then
            exit(0D);
        CalendarManagement.ReverseDateFormula(NegativeDateFormula, SourceServiceCommitment."Notice Period");
        CancellationPossibleUntil := CalcDate(NegativeDateFormula, CalculationStartDate);
        if DateTimeManagement.IsLastDayOfMonth(SourceServiceCommitment."Term Until") then
            DateTimeManagement.MoveDateToLastDayOfMonth(CancellationPossibleUntil);
    end;

    local procedure GetUpdatedTermUntilDate(CalculationStartDate: Date; SourceServiceCommitment: Record "Service Commitment") TermUntil: Date
    begin
        if (Format(SourceServiceCommitment."Extension Term") = '') or (CalculationStartDate = 0D) then
            exit(0D);
        TermUntil := CalcDate(SourceServiceCommitment."Extension Term", CalculationStartDate);
    end;

    local procedure MockServiceObjectWithEndUserCustomerNo(var ServiceObject: Record "Service Object"; CustomerNo: Code[20])
    begin
        ServiceObject.Init();
        ServiceObject.Validate("End-User Customer No.", CustomerNo);
        ServiceObject.Insert(true);
    end;

    local procedure ModifyCurrentServiceCommPackageLine(InitialTermDateFormulaText: Text; ExtensionTermDateFormulaText: Text; NoticePeriodDateFormulaText: Text; var ServiceCommPackageLine: Record "Service Comm. Package Line")
    begin
        if InitialTermDateFormulaText <> '' then
            Evaluate(ServiceCommPackageLine."Initial Term", InitialTermDateFormulaText);
        if ExtensionTermDateFormulaText <> '' then
            Evaluate(ServiceCommPackageLine."Extension Term", ExtensionTermDateFormulaText);
        if NoticePeriodDateFormulaText <> '' then
            Evaluate(ServiceCommPackageLine."Notice Period", NoticePeriodDateFormulaText);
        if (InitialTermDateFormulaText <> '') or (ExtensionTermDateFormulaText <> '') or (NoticePeriodDateFormulaText <> '') then
            ServiceCommPackageLine.Modify(false);
    end;

    local procedure SetupServiceObjectTemplatePackageAndAssignItemToPackage(var ServiceCommitmentTemplateCode: Code[20]; var ServiceObject: Record "Service Object"; var ServiceCommitmentPackage: Record "Service Commitment Package"; var ServiceCommPackageLine: Record "Service Comm. Package Line")
    var
        Item: Record Item;
        ServiceCommitmentTemplate: Record "Service Commitment Template";
    begin
        ContractTestLibrary.CreateServiceObjectWithItem(ServiceObject, Item, false);
        ServiceObject.SetHideValidationDialog(true);
        ContractTestLibrary.CreateServiceCommitmentTemplate(ServiceCommitmentTemplate);
        ContractTestLibrary.CreateServiceCommitmentPackageWithLine(ServiceCommitmentTemplateCode, ServiceCommitmentPackage, ServiceCommPackageLine);
        ContractTestLibrary.AssignItemToServiceCommitmentPackage(Item, ServiceCommitmentPackage.Code);
        ServiceCommitmentTemplateCode := ServiceCommitmentTemplate.Code;
    end;

    local procedure SetupServiceObjectWithServiceCommitment(var Item: Record Item; var ServiceObject: Record "Service Object"; SNSpecificTracking: Boolean; CreateWithAdditionalVendorServCommLine: Boolean)
    begin
        if CreateWithAdditionalVendorServCommLine then
            ContractTestLibrary.CreateServiceObjectWithItemAndWithServiceCommitment(ServiceObject, Enum::"Invoicing Via"::Contract, SNSpecificTracking, Item, 1, 1)
        else
            ContractTestLibrary.CreateServiceObjectWithItemAndWithServiceCommitment(ServiceObject, Enum::"Invoicing Via"::Contract, SNSpecificTracking, Item, 1, 0);
        ServiceObject.SetHideValidationDialog(true);
    end;

    local procedure TestCalculationBaseAmount(ServiceObjectQuantity: Decimal; ReferenceDate: Date; ExpectedPrice: Decimal; var ServiceObject: Record "Service Object"; var ServiceCommitmentPackage: Record "Service Commitment Package")
    var
        ServiceCommitment: Record "Service Commitment";
    begin
        ServiceObject.Validate("Quantity Decimal", ServiceObjectQuantity);
        ServiceObject.Modify(false);
        ServiceObject.InsertServiceCommitmentsFromServCommPackage(ReferenceDate, ServiceCommitmentPackage);
        FindServiceCommitment(ServiceCommitment, ServiceObject."No.");
        ServiceCommitment.FindFirst();
        ServiceCommitment.TestField("Calculation Base Amount", ExpectedPrice);
        ServiceCommitment.DeleteAll(false);
    end;

    local procedure TestServiceCommitmentTerminationDates(ServiceAndCalculationStartDate: Date; SourceServiceCommitment: Record "Service Commitment")
    var
        ExpectedDate: Date;
    begin
        if Format(SourceServiceCommitment."Initial Term") <> '' then
            ExpectedDate := GetCancellationPossibleUntilDate(ServiceAndCalculationStartDate, SourceServiceCommitment."Initial Term", SourceServiceCommitment."Extension Term", SourceServiceCommitment."Notice Period")
        else
            ExpectedDate := GetUpdatedCancellationPossibleUntilDate(SourceServiceCommitment."Term Until", SourceServiceCommitment);
        Assert.AreEqual(ExpectedDate, SourceServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" Date is not calculated correctly.');
        ExpectedDate := GetTermUntilDate(ServiceAndCalculationStartDate, SourceServiceCommitment."Service End Date", SourceServiceCommitment."Initial Term", SourceServiceCommitment."Extension Term", SourceServiceCommitment."Notice Period");
        Assert.AreEqual(ExpectedDate, SourceServiceCommitment."Term Until", '"Term Until" Date is not calculated correctly.');
    end;

    local procedure TestServiceCommitmentUpdatedTerminationDates(ServiceCommitment2: Record "Service Commitment"; SourceServiceCommitment: Record "Service Commitment"; ServiceCommitment: Record "Service Commitment")
    var
        ExpectedDate: Date;
    begin
        ExpectedDate := GetUpdatedTermUntilDate(ServiceCommitment2."Term Until", SourceServiceCommitment);
        Assert.AreEqual(ExpectedDate, SourceServiceCommitment."Term Until", '"Term Until" Date is not calculated correctly.');
        ExpectedDate := GetUpdatedCancellationPossibleUntilDate(SourceServiceCommitment."Term Until", ServiceCommitment);
        Assert.AreEqual(ExpectedDate, SourceServiceCommitment."Cancellation Possible Until", '"Cancellation Possible Until" Date is not calculated correctly.');
    end;

    local procedure ValidateServiceDateCombination(StartDate: Date; EndDate: Date; NextCalcDate: Date; ServiceObjectNo: Code[20])
    var
        ServiceCommitment: Record "Service Commitment";
    begin
        FindServiceCommitment(ServiceCommitment, ServiceObjectNo);
        Clear(ServiceCommitment."Service Start Date");
        Clear(ServiceCommitment."Service End Date");
        Clear(ServiceCommitment."Next Billing Date");
        ServiceCommitment."Service Start Date" := StartDate;
        ServiceCommitment."Service End Date" := EndDate;
        ServiceCommitment."Next Billing Date" := NextCalcDate;
        ServiceCommitment.Validate("Service End Date");
    end;

    #endregion Procedures

    #region Handlers

    [ModalPageHandler]
    procedure AssignServiceCommitmentsModalPageHandler(var AssignServiceCommitments: TestPage "Assign Service Commitments")
    begin
        AssignServiceCommitments.FieldServiceAndCalculationStartDate.SetValue(WorkDate());
        AssignServiceCommitments.First();
        AssignServiceCommitments.OK().Invoke();
    end;

    [ModalPageHandler]
    procedure ServiceObjectAttributeValueEditorModalPageHandlerExpectErrorOnPrimary(var ServiceObjectAttributeValueEditor: TestPage "Serv. Object Attr. Values")
    begin
        ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.First();
        asserterror ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Primary.SetValue(true);
    end;

    [ModalPageHandler]
    procedure ServiceObjectAttributeValueEditorModalPageHandlerTestValues(var ServiceObjectAttributeValueEditor: TestPage "Serv. Object Attr. Values")
    var
        ItemAttribute: array[2] of Record "Item Attribute";
        ItemAttributeValue: array[2] of Record "Item Attribute Value";
    begin
        ItemAttribute[1].Get(LibraryVariableStorage.DequeueInteger());
        ItemAttribute[2].Get(LibraryVariableStorage.DequeueInteger());
        ItemAttributeValue[1].Get(ItemAttribute[1].ID, LibraryVariableStorage.DequeueInteger());
        ItemAttributeValue[2].Get(ItemAttribute[2].ID, LibraryVariableStorage.DequeueInteger());

        ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.First();
        Assert.AreEqual(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList."Attribute Name".Value, ItemAttribute[1].Name, 'Unexpected Service Object Attribute Name');
        Assert.AreEqual(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Value.Value, ItemAttributeValue[1].Value, 'Unexpected Service Object Attribute Value');
        Assert.IsFalse(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Primary.AsBoolean(), 'Unexpected Service Object Attribute Primary value');
        ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Next();
        Assert.AreEqual(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList."Attribute Name".Value, ItemAttribute[2].Name, 'Unexpected Service Object Attribute Name');
        Assert.AreEqual(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Value.Value, ItemAttributeValue[2].Value, 'Unexpected Service Object Attribute Value');
        Assert.IsTrue(ServiceObjectAttributeValueEditor.ServiceObjectAttributeValueList.Primary.AsBoolean(), 'Unexpected Service Object Attribute Primary value');
    end;

    #endregion Handlers
}
