pageextension 50503 PostedTransferShipments extends "Posted Transfer Shipments"
{
    layout
    {
        addafter("Posting Date")
        {
            field("E - Invoicing QR Code"; Rec."E - Invoicing QR Code")
            {
                ToolTip = 'Specifies the value of the QR Code field.';
                ApplicationArea = All;
            }
            field("IRN No."; Rec."IRN No.")
            {
                ToolTip = 'Specifies the value of the IRN No. field.';
                ApplicationArea = All;
            }
            field("Transporter Code"; Rec."Transporter Code")
            {
                ApplicationArea = All;
                Editable = true;
            }
            field("EWay Bill No."; Rec."E-Way Bill No.")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the value of the EWay Bill No. field.';
            }
            field("E-Way Bill Date"; Rec."E-Way Bill Date")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the value of the E-Way Bill Date field.';
            }
            field("Cancel Reason"; Rec."Cancel Reason")
            {
                ApplicationArea = all;
            }
            field("E- Inv Cancelled Date"; Rec."E- Inv Cancelled Date")
            {
                ApplicationArea = all;
            }
        }
    }

    actions
    {
        addafter("&Print")
        {
            action(CreateIRNNo)
            {
                Caption = 'Create-IRN No';
                Promoted = true;
                ApplicationArea = All;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    CLEAR(APICall);
                    APICall.GenerateEInvoice(Rec."No.", 8, true);
                end;
            }
            action(CheckIRN)
            {
                Caption = 'Check-IRN';
                Promoted = true;
                ApplicationArea = All;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    CLEAR(APICall);
                    APICall.GenerateEInvoice(Rec."No.", 8, false);
                end;
            }
            action(CancelIRN)
            {
                Caption = 'Cancel IRN No.';
                Promoted = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    CLEAR(APICall);
                    rec.TESTFIELD("Reason Code");
                    APICall.CancelIRN(Rec."No.", 8, Rec."Transfer-from Code", Rec."Reason Code");
                end;
            }
            action("Get IRN By Doc No")
            {
                Caption = 'Get IRN By Doc No.';
                Promoted = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    CLEAR(APICall);
                    APICall.GetIRNByTyeDocDetails(Rec."No.", 8);
                    //LFS-5335 --
                end;
            }
            action("LUT IRN")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    Clear(APICall);
                    APICall.GenerateTrShipEinv(Rec);
                end;
            }


            action(ModifyTransferShipmentHeader)
            {
                Caption = 'Modify Transfer Shipment Header';
                Promoted = true;
                RunObject = Page "Modify TransferShipment Header";
                RunPageLink = "No." = field("No.");
                ApplicationArea = All;
            }

            action("Generate Invoice Detail")
            {
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GenerateInvoiceDetails(Rec."No.", 2);
                end;
            }
            action("Delivery Challan Invoice Details1")
            {
                ApplicationArea = All;
                Promoted = true;
                Caption = 'Delivery Challan Invoice Details';

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GenerateInvoiceDetailsInter(Rec."No.", 2);

                end;
            }
            action("JobWork InvoiceDetails")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    Clear(EwayBillAPI);
                    EwayBillAPI.GenerateInvoiceDetailsJB(Rec."No.", 2);
                end;
            }
            action("CalculateDistance")
            {
                Caption = 'Calculate Distance';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.CalculateDistance(Rec."No.", 2);
                end;
            }
            action("GeneratePartA")
            {
                Caption = 'Generate Part A';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GeneratePARTA(Rec."No.", 2);
                end;
            }
            action("DC GeneratePartA")
            {
                Caption = 'DC Generate Part A';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GeneratePARTAInter(Rec."No.", 2);
                end;
            }
            action("DownloadEWayBill")
            {
                ApplicationArea = All;
                Caption = 'Download E-Way Bill';
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "GenerateEwayStockTranfr Cloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.DownloadEwayBillPDF(Rec."No.", 2);

                end;
            }





        }
    }
}