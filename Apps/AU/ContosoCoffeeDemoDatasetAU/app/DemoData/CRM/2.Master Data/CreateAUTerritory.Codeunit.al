// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------

namespace Microsoft.DemoData.CRM;

using Microsoft.DemoTool.Helpers;

codeunit 17128 "Create AU Territory"
{
    InherentEntitlements = X;
    InherentPermissions = X;

    trigger OnRun()
    var
        ContosoCRM: Codeunit "Contoso CRM";
    begin
        ContosoCRM.SetOverwriteData(true);
        ContosoCRM.InsertTerritory(Domestic(), DomesticLbl);
        ContosoCRM.SetOverwriteData(false);
    end;

    procedure Domestic(): Code[10]
    begin
        exit(DomesticTok);
    end;

    var
        DomesticTok: Label 'DOMESTIC', MaxLength = 10;
        DomesticLbl: Label 'Domestic', MaxLength = 50;
}
