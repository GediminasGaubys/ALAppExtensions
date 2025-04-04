﻿#if not CLEANSCHEMA26
// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Finance.VAT.Reporting;

using Microsoft.Finance.VAT.Setup;

tableextension 10687 "Elec. VAT Code" extends "VAT Code"
{
    fields
    {
        field(10680; "VAT Rate For Reporting"; Decimal)
        {
            Caption = 'VAT Rate For Reporting';
            ObsoleteReason = 'Use the table "VAT Reporting Code" instead.';
            ObsoleteState = Removed;
            ObsoleteTag = '26.0';
        }
        field(10681; "Report VAT Rate"; Boolean)
        {
            Caption = 'Report VAT Rate';
            ObsoleteReason = 'Use the table "VAT Reporting Code" instead.';
            ObsoleteState = Removed;
            ObsoleteTag = '26.0';
        }
    }
}
#endif