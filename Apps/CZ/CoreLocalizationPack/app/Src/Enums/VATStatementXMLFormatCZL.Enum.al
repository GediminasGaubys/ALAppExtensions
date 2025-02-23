﻿// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Finance.VAT.Reporting;

enum 11770 "VAT Statement XML Format CZL" implements "VAT Statement Export CZL"
{
    Extensible = true;

    value(0; DPHDP3)
    {
        Caption = 'DPHDP3 v2';
        Implementation = "VAT Statement Export CZL" = "VAT Statement DPHDP3 CZL";
    }
    value(1; DPHDP3v3)
    {
        Caption = 'DPHDP3 v3';
        Implementation = "VAT Statement Export CZL" = "VAT Statement DPHDP3v3 CZL";
    }
}
