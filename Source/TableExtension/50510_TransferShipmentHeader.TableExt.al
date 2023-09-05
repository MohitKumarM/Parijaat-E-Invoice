tableextension 50510 TransferShipmentHedaer extends "Transfer Shipment Header"
{
    fields
    {
        field(50500; "IRN No."; Text[70])
        {
            DataClassification = ToBeClassified;
        }
        field(50501; "Ack No."; text[20])
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
        field(50104; "E - Invoicing QR Code"; Blob)
        {
            Subtype = Bitmap;
            DataClassification = ToBeClassified;
        }
        field(50505; "E-Way Bill No."; Text[70])
        {
            DataClassification = ToBeClassified;
        }
        field(50506; "E-Way Bill Date"; DateTime)
        {
            DataClassification = ToBeClassified;
        }

        field(50107; "Cancel Reason"; Enum "e-Invoice Cancel Reason")
        {
            DataClassification = ToBeClassified;
        }
        field(50108; "E- Inv Cancelled Date"; DateTime)
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}