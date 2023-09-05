tableextension 50509 SalesCrMemoHeader extends "Sales Cr.Memo Header"
{
    fields
    {
        field(50100; "IRN No."; Text[70])
        {
            DataClassification = ToBeClassified;
        }
        field(50101; "Ack No."; text[20])
        {
            DataClassification = ToBeClassified;
        }
        field(50502; "AcK Date"; DateTime)
        {
            DataClassification = ToBeClassified;
        }
        field(50503; "Cancel Remarks"; Enum "Cancel Remarks")
        {
            DataClassification = ToBeClassified;
        }
        field(50504; "E - Invoicing QR Code"; Blob)
        {
            Subtype = Bitmap;
            DataClassification = ToBeClassified;
        }
        field(50505; "E-Way Bill Date"; DateTime)
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}