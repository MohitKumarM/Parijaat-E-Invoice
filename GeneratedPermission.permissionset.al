permissionset 50000 GeneratedPermission
{
    Assignable = true;
    Permissions = tabledata "E-Invoice Set Up 1" = RIMD,
        table "E-Invoice Set Up 1" = X,
        codeunit "E Way Bill Generation" = X,
        codeunit "E-Invoice Generation" = X,
        codeunit "Generate EwaySalesInvoiceCloud" = X,
        codeunit "GenerateEwayStockTranfr Cloud" = X,
        codeunit "ROBOAPI Call Cloud" = X,
        page "E-Invoice API Set Up" = X,
        page "Modify Sales Cr Memo Header" = X,
        page "Modify Sales Inv Header" = X,
        page "Modify TransferShipment Header" = X;
}