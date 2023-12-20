codeunit 50401 "ROBOAPI Call Cloud"
{
    // LFS-5335 : New Codeunit created for IRN Generation & IRN Cancel Functionality.
    // LFS-6587 : New function for generating B2C QR code added.

    Permissions = TableData 112 = rm, TableData 50014 = rmi, tabledata 50300 = rimd;

    trigger OnRun()
    begin
    end;

    var

        ROBOSetup: Record "GST Registration Nos.";
        GlbTextVar: Text;
        GSTAmt: array[3] of Decimal;
        StoreOutStrm: OutStream;
        CompInfo: Record 79;
        Char10: Char;
        Char13: Char;
        NewLine: Text;
        ErrorLogMessage: Text;
        MessageID: Text;
        ReturnMessage: Text;
        IRNMsg: Label 'IRN No. has been Generated.';
        CancelMsg: Label 'IRN No. has been cancel.';

    procedure GenerateEInvoice(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt"; SendRequest: Boolean)
    var
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        TransferShipmentHeader: Record "Transfer Shipment Header";
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        AckNo: Code[20];
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        DigitalSignBstr: BigText;
        QRCodeBstr: BigText;
        TaxProOutput: Record 50014;
        oStream: OutStream;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        IRNStatus: Text;
        DayCode: Integer;
        AckDateText: Text;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLInfo: Record "Detailed GST Ledger Entry Info";
        GSTRegistrationNos: Record "GST Registration Nos.";
        Location: Record Location;
        OutSrm: OutStream;
        Contries: Record "Country/Region";
        TrShip_From: Record "Transfer Shipment Header";
        Customer: Record Customer;
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("E-Invoice URl");
        EInvoiceSetUp.TestField("Client ID");
        EInvoiceSetUp.TestField("Client Secret");
        EInvoiceSetUp.TestField("IP Address");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        CheckIfCancelled(DocNo);

        DtldGSTLedgerEntry.RESET;
        // 15800 DtldGSTLedgerEntry.SETRANGE("Original Doc. Type", DocType);
        //DtldGSTLedgerEntry.SetRange("Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            if DGLInfo.Get(DtldGSTLedgerEntry."Entry No.") then;
            DGLInfo.SetRange("Original Doc. Type", DocType);
            if not DGLInfo.FindFirst() then
                exit;
            Authenticate(DtldGSTLedgerEntry."Location  Reg. No.");
            GlbTextVar := '';
            //Write Common Details
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'INVOICE', 0, TRUE);
            WriteToGlbTextVar('Version', '1.1', 0, TRUE);
            WriteToGlbTextVar('Irn', '', 0, TRUE);

            //Write TpApiTranDtls
            GlbTextVar += '"TpApiTranDtls": {';
            WriteTransDtls(DtldGSTLedgerEntry);
            GlbTextVar += '},';

            //Write TpApiDocDtls
            GlbTextVar += '"TpApiDocDtls": {';
            WriteDocDtls(DtldGSTLedgerEntry);
            GlbTextVar += '},';

            //Write SellerDtls
            GlbTextVar += '"TpApiSellerDtls": {';
            WriteSellerDtls(DtldGSTLedgerEntry);
            GlbTextVar += '},';

            //Write ShipDtls
            CASE DocType OF
                DocType::Invoice:
                    BEGIN
                        SalesInvoiceHeader.GET(DocNo);
                        IF SalesInvoiceHeader."Ship-to Code New" = '' THEN BEGIN
                            IF SalesInvoiceHeader."Ship-to Code" <> '' THEN BEGIN
                                GlbTextVar += '"TpApiBuyerDtls": {';
                                WriteBuyersDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';

                                if SalesInvoiceHeader.Alternative <> '' then begin
                                    GlbTextVar += '"TpApiDispDtls": {';
                                    WriteDispatchDtls(DtldGSTLedgerEntry);
                                    GlbTextVar += '},';
                                end;



                                GlbTextVar += '"TpApiShipDtls": {';
                                WriteShipDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';
                            END ELSE BEGIN
                                GlbTextVar += '"TpApiBuyerDtls": {';

                                WriteBuyersDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';

                                if SalesInvoiceHeader.Alternative <> '' then begin
                                    GlbTextVar += '"TpApiDispDtls": {';
                                    WriteDispatchDtls(DtldGSTLedgerEntry);
                                    GlbTextVar += '},';
                                end;

                            END;
                        END ELSE BEGIN
                            GlbTextVar += '"TpApiBuyerDtls": {';
                            WriteBuyersNewDtls(DtldGSTLedgerEntry);
                            GlbTextVar += '},';

                            GlbTextVar += '"TpApiShipDtls": {';
                            WriteShipDtlsNew(DtldGSTLedgerEntry);
                            GlbTextVar += '},';
                        END;
                    END;
                DocType::"Credit Memo":
                    BEGIN
                        SalesCrMemoHeader.GET(DocNo);
                        IF SalesCrMemoHeader."Ship-to Code New" = '' THEN BEGIN
                            IF SalesCrMemoHeader."Ship-to Code" <> '' THEN BEGIN
                                GlbTextVar += '"TpApiBuyerDtls": {';
                                WriteBuyersDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';

                                GlbTextVar += '"TpApiShipDtls": {';
                                WriteShipDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';
                            END ELSE BEGIN
                                GlbTextVar += '"TpApiBuyerDtls": {';
                                WriteBuyersDtls(DtldGSTLedgerEntry);
                                GlbTextVar += '},';
                            END;
                        END ELSE BEGIN
                            GlbTextVar += '"TpApiBuyerDtls": {';
                            WriteBuyersNewDtls(DtldGSTLedgerEntry);
                            GlbTextVar += '},';

                            GlbTextVar += '"TpApiShipDtls": {';
                            WriteShipDtlsNew(DtldGSTLedgerEntry);
                            GlbTextVar += '},';
                        END;
                    END;
                DocType::"Transfer Shipment":
                    BEGIN
                        GlbTextVar += '"TpApiBuyerDtls": {';
                        WriteBuyerDtls(DtldGSTLedgerEntry);
                        GlbTextVar += '},';
                        if TransferShipmentHeader.Get(DocNo) then;

                        if TransferShipmentHeader.Alternative <> '' then begin
                            GlbTextVar += '"TpApiDispDtls": {';
                            WriteDispatchDtls(DtldGSTLedgerEntry);
                            GlbTextVar += '},';
                        end;

                        //Write Export Details
                        if TrShip_From.Get(DtldGSTLedgerEntry."Document No.") then begin
                            IF TrShip_From."Transfer Order Export" THEN BEGIN
                                if Customer.GET(TrShip_From."To-Transaction Source Code") then;
                                if Contries.Get(Customer."Country/Region Code") then;
                                GlbTextVar += '"TpApiExpDtls": {';
                                WriteToGlbTextVar('CountryCode', Contries."Country Code for E-Invoicing", 0, false);
                                GlbTextVar += '},';
                            end;
                        end;

                    END;
            END;
            //Write ValDtls

            //Write ValDtls
            GlbTextVar += '"TpApiValDtls": {';
            WriteValDtls(DtldGSTLedgerEntry);
            GlbTextVar += '},';

            //Write ItemList
            GlbTextVar += '"TpApiItemList": [';
            WriteItemList(DtldGSTLedgerEntry);
            GlbTextVar += ']';
            GlbTextVar += '}';

            MESSAGE(GlbTextVar);
            /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD(ROBOSetup.client_id);
            ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
 */ // 15800
            if SendRequest then begin
                IF Location.GET(DtldGSTLedgerEntry."Location Code") THEN;
                GSTRegistrationNos.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
                EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
                EinvoiceHttpHeader.Clear();
                EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
                EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
                EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
                EinvoiceHttpHeader.Add('Content-Type', 'application/json');
                EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."E-Invoice User Name");
                EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
                EinvoiceHttpRequest.Content := EinvoiceHttpContent;
                EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
                EinvoiceHttpRequest.Method := 'POST';
                if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                    EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                    JResultObject.ReadFrom(ResultMessage);
                    Char13 := 13;
                    Char10 := 10;
                    NewLine := FORMAT(Char10) + FORMAT(Char13);
                    ErrorLogMessage += NewLine + 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
              + ResultMessage + NewLine + '-----------------------------------------------------------';

                    if JResultObject.Get('MessageId', JResultToken) then
                        MessageID := JResultToken.AsValue().AsText();
                    if JResultToken.AsValue().AsInteger() = 1 then begin
                        if JResultObject.Get('Message', JResultToken) then;
                        //Message(Format(JResultToken));
                    end else
                        if JResultObject.Get('Message', JResultToken) then
                            //Message(Format(JResultToken));
                            ReturnMessage := JResultToken.AsValue().AsText();

                    if JResultObject.Get('Data', JResultToken) then
                        if JResultToken.IsObject then begin
                            JResultToken.WriteTo(OutputMessage);
                            JOutputObject.ReadFrom(OutputMessage);
                            if JOutputObject.Get('AckDt', JOutputToken) then
                                AckDateText := JOutputToken.AsValue().AsText();
                            Evaluate(YearCode, CopyStr(AckDateText, 1, 4));
                            Evaluate(MonthCode, CopyStr(AckDateText, 6, 2));
                            Evaluate(DayCode, CopyStr(AckDateText, 9, 2));
                            Evaluate(AckDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(AckDateText, 12, 8));
                            if JOutputObject.Get('Irn', JOutputToken) then
                                IRNNo := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('SignedQRCode', JOutputToken) then
                                QRText := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('AckNo', JOutputToken) then
                                AckNo := JOutputToken.AsValue().AsCode();
                            if JOutputObject.Get('Status', JOutputToken) then
                                IRNStatus := JOutputToken.AsValue().AsText();
                        end;
                end;
                /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                           RetVal := ROBODLL.GenerateIRN(GlbTextVar,
                                                         ROBOSetup.client_id,
                                                         ROBOSetup.client_secret,
                                                         ROBOSetup.IPAddress,
                                                         ROBOSetup.user_name,
                                                         ROBOSetup.Gstin,
                                                         ROBOSetup."Error File Save Path",
                                                         IRNText,
                                                         RQRCode,
                                                         AckNo,
                                                         AckDt,
                                                         IRNStatus,
                                                         MessageID,
                                                         ReturnMessage,
                                                         ROBOSetup."URL E-Inv");
                             //MESSAGE('JSON '+ GlbTextVar);
                             //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/

                TaxProOutput.INIT;
                TaxProOutput."Document Type" := DocType;
                TaxProOutput."Document No." := DocNo;
                TaxProOutput."IRN No." := IRNNo;
                TaxProOutput."Ack Nos" := AckNo;
                TaxProOutput."Ack Date" := format(AckDate);
                TaxProOutput."IRN Status" := IRNStatus;
                TaxProOutput."Message Id" := MessageID;

                IF QRCodeBstr.LENGTH > 0 THEN BEGIN
                    TaxProOutput."QR Code".CREATEOUTSTREAM(oStream);
                    QRCodeBstr.WRITE(oStream);
                END;
                IF DigitalSignBstr.LENGTH > 0 THEN BEGIN
                    TaxProOutput."Digital Signature".CREATEOUTSTREAM(oStream);
                    DigitalSignBstr.WRITE(oStream);
                END;
                if QRText = '' then begin
                    Clear(TaxProOutput."QR Code Temp");
                end;
                TaxProOutput.JSON.CreateOutStream(OutSrm);
                OutSrm.WriteText(GlbTextVar);
                TaxProOutput."Output Payload E-Invoice".CreateOutStream(StoreOutStrm);
                StoreOutStrm.WriteText(ErrorLogMessage);
                IF NOT TaxProOutput.INSERT THEN
                    TaxProOutput.MODIFY;

                Clear(RecRef);
                RecRef.Get(SalesInvoiceHeader.RecordId);
                if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
                    if TempBlob.HasValue() then begin
                        FldRef := RecRef.Field(SalesInvoiceHeader.FieldNo("QR Code"));
                        TempBlob.ToRecordRef(RecRef, SalesInvoiceHeader.FieldNo("QR Code"));
                        RecRef.Field(SalesInvoiceHeader.FieldNo("IRN No.")).Value := IRNNo;
                        RecRef.Field(SalesInvoiceHeader.FieldNo("Ack No.")).Value := AckNo;
                        RecRef.Field(SalesInvoiceHeader.FieldNo("Ack Date")).Value := AckDate;
                        RecRef.Modify();
                    end;
                end;
                Clear(RecRef);
                RecRef.Get(TaxProOutput.RecordId);
                if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
                    if TempBlob.HasValue() then begin
                        FldRef := RecRef.Field(TaxProOutput.FieldNo("QR Code Temp"));
                        TempBlob.ToRecordRef(RecRef, TaxProOutput.FieldNo("QR Code Temp"));
                        RecRef.Modify();
                    end;
                END;

                IF MessageID = '1' THEN BEGIN
                    MESSAGE(IRNMsg);
                END ELSE
                    MESSAGE(ReturnMessage);

            end;
        end;

    end;

    procedure CancelIRN(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt"; LocCode: Code[20]; CancelCode: Code[20])
    var
        TaxProOutput: Record 50014;
        CancelDateErr: Label 'IRN is already cancelled.';
        ReasonCode: Record 231;
        L_Message: Text;
        Location: Record 14;
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        GSTRegistrationNos: Record "GST Registration Nos.";
        CancelDateText: Text;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        CancelDateTime: DateTime;
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("E-Invoice URl");
        EInvoiceSetUp.TestField("Client ID");
        EInvoiceSetUp.TestField("Client Secret");
        EInvoiceSetUp.TestField("IP Address");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");
        Location.GET(LocCode);
        Authenticate(Location."GST Registration No.");
        if GSTRegistrationNos.GET(Location."GST Registration No.") then;

        TaxProOutput.RESET;
        TaxProOutput.SETRANGE(TaxProOutput."Document Type", DocType);
        TaxProOutput.SETRANGE(TaxProOutput."Document No.", DocNo);
        IF TaxProOutput.FINDSET THEN BEGIN
            ReasonCode.GET(CancelCode);
            IF TaxProOutput."Cancellation Date" <> '' THEN
                ERROR(CancelDateErr);

            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'CANCEL', 0, TRUE);
            WriteToGlbTextVar('IRNNo', TaxProOutput."IRN No.", 0, TRUE);
            WriteToGlbTextVar('CancelReason', FORMAT(ReasonCode."Einvoice Code"), 0, TRUE);
            WriteToGlbTextVar('CancelRemarks', ReasonCode.Description, 0, FALSE);
            GlbTextVar += '}';
            Message(GlbTextVar);

            EinvoiceHttpContent.WriteFrom(GlbTextVar);
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
            EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
            EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."E-Invoice User Name");
            EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
            EinvoiceHttpRequest.Method := 'POST';
            if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                JResultObject.ReadFrom(ResultMessage);
                if JResultObject.Get('MessageId', JResultToken) then
                    MessageID := JResultToken.AsValue().AsText();
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        L_Message := JResultToken.AsValue().AsText();

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsObject then begin
                        JResultToken.WriteTo(OutputMessage);
                        JOutputObject.ReadFrom(OutputMessage);
                        if JOutputObject.Get('CancelDate', JOutputToken) then
                            CancelDateText := JOutputToken.AsValue().AsText();
                        Evaluate(YearCode, CopyStr(CancelDateText, 1, 4));
                        Evaluate(MonthCode, CopyStr(CancelDateText, 6, 2));
                        Evaluate(DayCode, CopyStr(CancelDateText, 9, 2));
                        Evaluate(CancelDateTime, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(CancelDateText, 12, 8));
                        JOutputObject.Get('Irn', JOutputToken);
                        IRNNo := JOutputToken.AsValue().AsText();
                    end;
            end else
                Message(GetLastErrorText());

            //MESSAGE(GlbTextVar);
            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
              ROBODLL := ROBODLL.ROBO();
              ROBODLL.CancelIRN(GlbTextVar,
                                ROBOSetup.client_id,
                                ROBOSetup.client_secret,
                                ROBOSetup.IPAddress,
                                ROBOSetup.user_name,
                                ROBOSetup.Gstin,
                                ROBOSetup."Error File Save Path",
                                IRNText,
                                CancelDt,
                                MessageID,
                                L_Message,
                                IRNStatus,
                                ROBOSetup."URL CanE-Inv");
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            IF MessageID = '1' THEN BEGIN
                TaxProOutput."Cancellation Date" := FORMAT(CancelDateTime);
                TaxProOutput."IRN Status" := 'CAN';
                //TaxProOutput."Message Response" := L_Message;
                TaxProOutput.MODIFY;
                MESSAGE(CancelMsg);
            END ELSE
                ERROR(L_Message);
        END;
    end;

    procedure GetIRNByDocDetails(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        IRNText: Text;
        DigitalSignBstr: BigText;
        QRCodeBstr: BigText;
        TaxProOutput: Record 50014;
        oStream: OutStream;
        AckNo: Text;
        AckDt: Text;
        IRNStatus: Text;
        DetailedGSTLedgerInfo: Record "Detailed GST Ledger Entry Info";
    begin
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        CheckIfCancelled(DocNo);

        DtldGSTLedgerEntry.RESET;
        // 15800   DtldGSTLedgerEntry.SETRANGE("Original Doc. Type", DocType);
        // DtldGSTLedgerEntry.SetRange("Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            if DetailedGSTLedgerInfo.Get(DtldGSTLedgerEntry."Entry No.") then;
            DetailedGSTLedgerInfo.SetRange("Original Doc. Type", DocType);
            if not DetailedGSTLedgerInfo.FindFirst() then
                exit;

            Authenticate(DtldGSTLedgerEntry."Location  Reg. No.");
            GlbTextVar := '';
            //Write Common Details
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'INVOICEDTLS', 0, TRUE);
            WriteToGlbTextVar('DocNo', DtldGSTLedgerEntry."Document No.", 0, TRUE);
            WriteToGlbTextVar('DocDate', FORMAT(DtldGSTLedgerEntry."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>'), 0, TRUE);
            WriteToGlbTextVar('TYP', FORMAT(DetailedGSTLedgerInfo."Nature of Supply"), 0, FALSE);
            GlbTextVar += '}';

            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD(ROBOSetup.client_id);
            ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
            //MESSAGE(GlbTextVar);
            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
            RetVal := ROBODLL.GetEInvoiceDetailsbyDocNo(GlbTextVar,
                                          ROBOSetup.client_id,
                                          ROBOSetup.client_secret,
                                          ROBOSetup.IPAddress,
                                          ROBOSetup.user_name,
                                          ROBOSetup.Gstin,
                                          ROBOSetup."Error File Save Path",
                                          IRNText,
                                          RQRCode,
                                          AckNo,
                                          AckDt,
                                          IRNStatus,
                                          MessageID,
                                          ReturnMessage,
                                          ROBOSetup."URL E-Inv");

        //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            TaxProOutput.INIT;
            TaxProOutput."Document Type" := DocType;
            TaxProOutput."Document No." := DocNo;
            TaxProOutput."IRN No." := IRNText;
            TaxProOutput."Ack Nos" := AckNo;
            TaxProOutput."Ack Date" := AckDt;
            TaxProOutput."IRN Status" := IRNStatus;
            TaxProOutput."Message Id" := MessageID;
            //TaxProOutput."Message Response" := ReturnMessage;
            IF QRCodeBstr.LENGTH > 0 THEN BEGIN
                TaxProOutput."QR Code".CREATEOUTSTREAM(oStream);
                QRCodeBstr.WRITE(oStream);
            END;
            IF DigitalSignBstr.LENGTH > 0 THEN BEGIN
                TaxProOutput."Digital Signature".CREATEOUTSTREAM(oStream);
                DigitalSignBstr.WRITE(oStream);
            END;
            IF MessageID = '1' THEN BEGIN
                /*     CreateTempQRCode(TempBlob, RQRCode);
                    TaxProOutput."QR Code Temp" := TempBlob.Blob; */ // 15800
                MESSAGE(ReturnMessage);
            END ELSE
                MESSAGE(ReturnMessage);

            IF NOT TaxProOutput.INSERT THEN
                TaxProOutput.MODIFY;
        END;
    end;

    procedure GetIRNByTyeDocDetails(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
    var
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        AckNo: Code[20];
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;

        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        DigitalSignBstr: BigText;
        QRCodeBstr: BigText;
        TaxProOutput: Record 50014;
        oStream: OutStream;
        AckDateText: Text;
        DayCode: Integer;
        IRNStatus: Text;
        GSTRegistrationNos: Record "GST Registration Nos.";
        Location: Record Location;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        SalesInvoiceHeader: Record "Sales Invoice Header";
        OutSrm: OutStream;
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("URL Get IRN");
        EInvoiceSetUp.TestField("Client ID");
        EInvoiceSetUp.TestField("Client Secret");
        EInvoiceSetUp.TestField("IP Address");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        CheckIfCancelled(DocNo);

        DtldGSTLedgerEntry.RESET;
        // 15800  DtldGSTLedgerEntry.SETRANGE("Original Doc. Type", DocType);
        // DtldGSTLedgerEntry.SetRange("Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            if DGLInfo.Get(DtldGSTLedgerEntry."Entry No.") then;
            DGLInfo.SetRange("Original Doc. Type", DocType);
            if not DGLInfo.FindFirst() then
                exit;

            Authenticate(DtldGSTLedgerEntry."Location  Reg. No.");
            GlbTextVar := '';
            //Write Common Details
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'IRNBYDOCDETAILS', 0, TRUE);
            WriteToGlbTextVar('doctype', FORMAT(GetDocType(DtldGSTLedgerEntry)), 0, TRUE);
            WriteToGlbTextVar('docnum', DtldGSTLedgerEntry."Document No.", 0, TRUE);
            WriteToGlbTextVar('docdate', FORMAT(DtldGSTLedgerEntry."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>'), 0, FALSE);

            GlbTextVar += '}';

            /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD(ROBOSetup.client_id);
            ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
                                                        //  MESSAGE(GlbTextVar);
                                                        /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                                                        RetVal := ROBODLL.GetEInvoiceDetailsbyDocNo(GlbTextVar,
                                                                                      ROBOSetup.client_id,
                                                                                      ROBOSetup.client_secret,
                                                                                      ROBOSetup.IPAddress,
                                                                                      ROBOSetup.user_name,
                                                                                      ROBOSetup.Gstin,
                                                                                      ROBOSetup."Error File Save Path",
                                                                                      IRNText,
                                                                                      RQRCode,
                                                                                      AckNo,
                                                                                      AckDt,
                                                                                      IRNStatus,
                                                                                      MessageID,
                                                                                      ReturnMessage,
                                                                                      ROBOSetup."URL Get IRN");
                                                    //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            IF Location.GET(DtldGSTLedgerEntry."Location Code") THEN;
            GSTRegistrationNos.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
            EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
            EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."E-Invoice User Name");
            EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."URL Get IRN");
            EinvoiceHttpRequest.Method := 'POST';
            if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                JResultObject.ReadFrom(ResultMessage);
                Char13 := 13;
                Char10 := 10;
                NewLine := FORMAT(Char10) + FORMAT(Char13);
                ErrorLogMessage += NewLine + 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine +
                ResultMessage + NewLine + '-----------------------------------------------------------';

                if JResultObject.Get('MessageId', JResultToken) then
                    MessageID := JResultToken.AsValue().AsText();
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then
                        ReturnMessage := JResultToken.AsValue().AsText();
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        //Message(Format(JResultToken));
                      ReturnMessage := JResultToken.AsValue().AsText();

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsObject then begin
                        JResultToken.WriteTo(OutputMessage);
                        JOutputObject.ReadFrom(OutputMessage);
                        if JOutputObject.Get('AckDt', JOutputToken) then
                            AckDateText := JOutputToken.AsValue().AsText();
                        Evaluate(YearCode, CopyStr(AckDateText, 1, 4));
                        Evaluate(MonthCode, CopyStr(AckDateText, 6, 2));
                        Evaluate(DayCode, CopyStr(AckDateText, 9, 2));
                        Evaluate(AckDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(AckDateText, 12, 8));
                        if JOutputObject.Get('Irn', JOutputToken) then
                            IRNNo := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('SignedQRCode', JOutputToken) then
                            QRText := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('AckNo', JOutputToken) then
                            AckNo := JOutputToken.AsValue().AsCode();
                        if JOutputObject.Get('Status', JOutputToken) then
                            IRNStatus := JOutputToken.AsValue().AsText();
                    end;
            end;
            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                       RetVal := ROBODLL.GenerateIRN(GlbTextVar,
                                                     ROBOSetup.client_id,
                                                     ROBOSetup.client_secret,
                                                     ROBOSetup.IPAddress,
                                                     ROBOSetup.user_name,
                                                     ROBOSetup.Gstin,
                                                     ROBOSetup."Error File Save Path",
                                                     IRNText,
                                                     RQRCode,
                                                     AckNo,
                                                     AckDt,
                                                     IRNStatus,
                                                     MessageID,
                                                     ReturnMessage,
                                                     ROBOSetup."URL E-Inv");
                         //MESSAGE('JSON '+ GlbTextVar);
                         //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/

            TaxProOutput.INIT;
            TaxProOutput."Document Type" := DocType;
            TaxProOutput."Document No." := DocNo;
            TaxProOutput."IRN No." := IRNNo;
            TaxProOutput."Ack Nos" := AckNo;
            TaxProOutput."Ack Date" := format(AckDate);
            TaxProOutput."IRN Status" := IRNStatus;
            TaxProOutput."Message Id" := MessageID;

            IF QRCodeBstr.LENGTH > 0 THEN BEGIN
                TaxProOutput."QR Code".CREATEOUTSTREAM(oStream);
                QRCodeBstr.WRITE(oStream);
            END;
            IF DigitalSignBstr.LENGTH > 0 THEN BEGIN
                TaxProOutput."Digital Signature".CREATEOUTSTREAM(oStream);
                DigitalSignBstr.WRITE(oStream);
            END;
            TaxProOutput."Output Payload E-Invoice".CreateOutStream(StoreOutStrm);
            StoreOutStrm.WriteText(ResultMessage);
            TaxProOutput.JSON.CreateOutStream(OutSrm);
            OutSrm.WriteText(GlbTextVar);
            IF MessageID = '1' THEN BEGIN
                MESSAGE(ReturnMessage);
            END ELSE
                MESSAGE(ReturnMessage);
            IF NOT TaxProOutput.INSERT THEN
                TaxProOutput.MODIFY;

            Clear(RecRef);
            RecRef.Get(SalesInvoiceHeader.RecordId);
            if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
                if TempBlob.HasValue() then begin
                    FldRef := RecRef.Field(SalesInvoiceHeader.FieldNo("QR Code"));
                    TempBlob.ToRecordRef(RecRef, SalesInvoiceHeader.FieldNo("QR Code"));
                    RecRef.Field(SalesInvoiceHeader.FieldNo("IRN No.")).Value := IRNNo;
                    RecRef.Field(SalesInvoiceHeader.FieldNo("Ack No.")).Value := AckNo;
                    RecRef.Field(SalesInvoiceHeader.FieldNo("Ack Date")).Value := AckDate;
                    RecRef.Modify();
                end;
            end;

            Clear(RecRef);
            RecRef.Get(TaxProOutput.RecordId);
            if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
                if TempBlob.HasValue() then begin
                    FldRef := RecRef.Field(TaxProOutput.FieldNo("QR Code Temp"));
                    TempBlob.ToRecordRef(RecRef, TaxProOutput.FieldNo("QR Code Temp"));
                    RecRef.Modify();
                end;
            END;
        end;
    END;

    local procedure Authenticate(GSTIN: Code[20])
    var
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("E-Invoice URl");
        EInvoiceSetUp.TestField("Client ID");
        EInvoiceSetUp.TestField("Client Secret");
        EInvoiceSetUp.TestField("IP Address");
        EinvoiceHttpContent.WriteFrom(SetEinvoiceUserIDandPassword(GSTIN));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."Authentication URL");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            Char13 := 13;
            Char10 := 10;
            NewLine := FORMAT(Char10) + FORMAT(Char13);

            ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine +
            ResultMessage + NewLine + '-----------------------------------------------------------';
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken)); //TEAM 14763
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));
            if JResultToken.IsObject then begin
                JResultToken.WriteTo(OutputMessage);
                JOutputObject.ReadFrom(OutputMessage);
            end;
        end else
            Message('Authentication Failed');
    end;

    procedure SetEinvoiceUserIDandPassword(GSTIN: Code[16]) JsonTxt: Text

    var
        JsonObj: JsonObject;
        GSTRegistrationNos: Record "GST Registration Nos.";
    begin
        if GSTRegistrationNos.Get(GSTIN) then;
        JsonObj.Add('action', 'ACCESSTOKEN');
        JsonObj.Add('UserName', GSTRegistrationNos."E-Invoice User Name");
        JsonObj.Add('Password', GSTRegistrationNos.Password);
        JsonObj.Add('Gstin', GSTRegistrationNos.Code);
        JsonObj.WriteTo(JsonTxt);
        // Message(JsonTxt); //TEAM 14763
    end;

    local procedure WriteTransDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        TransShipHead: Record 5744;
        DetailedGSTLedgerInfo: Record "Detailed GST Ledger Entry Info";
    begin
        if DetailedGSTLedgerInfo.Get(DtldGSTLedgEntry."Entry No.") then; // 15800
        CASE DetailedGSTLedgerInfo."Original Doc. Type" OF
            DetailedGSTLedgerInfo."Original Doc. Type"::Invoice,
            DetailedGSTLedgerInfo."Original Doc. Type"::"Credit Memo":
                BEGIN
                    Customer.GET(DtldGSTLedgEntry."Source No.");

                    IF DtldGSTLedgEntry."Reverse Charge" THEN
                        WriteToGlbTextVar('RevReverseCharge', 'Y', 0, TRUE)
                    ELSE
                        WriteToGlbTextVar('RevReverseCharge', 'N', 0, TRUE);

                    CASE DtldGSTLedgEntry."GST Customer Type" OF
                        DtldGSTLedgEntry."GST Customer Type"::Registered,
                        DtldGSTLedgEntry."GST Customer Type"::Unregistered,
                        DtldGSTLedgEntry."GST Customer Type"::"SEZ Development",
                        DtldGSTLedgEntry."GST Customer Type"::"SEZ Unit":
                            IF (Customer."GST Registration Type" = Customer."GST Registration Type"::GSTIN) THEN
                                WriteToGlbTextVar('Typ', 'B2B', 0, TRUE)
                            else
                                IF (Customer."GST Registration Type" = Customer."GST Registration Type"::GID) THEN
                                    WriteToGlbTextVar('Typ', 'B2G', 0, TRUE)
                                else
                                    IF DtldGSTLedgEntry."GST Without Payment of Duty" THEN
                                        WriteToGlbTextVar('Typ', 'SEZWP', 0, TRUE)
                                    else
                                        WriteToGlbTextVar('Typ', 'SEZWOP', 0, TRUE);
                        DtldGSTLedgEntry."GST Customer Type"::Export:
                            IF DtldGSTLedgEntry."GST Without Payment of Duty" THEN
                                WriteToGlbTextVar('Typ', 'EXPWP', 0, TRUE)
                            else
                                WriteToGlbTextVar('Typ', 'EXPWOP', 0, TRUE);
                        DtldGSTLedgEntry."GST Customer Type"::"Deemed Export":
                            WriteToGlbTextVar('Typ', 'DEXP', 0, TRUE);
                    END;
                END;

            DetailedGSTLedgerInfo."Original Doc. Type"::"Transfer Shipment":
                BEGIN
                    TransShipHead.GET(DtldGSTLedgEntry."Document No.");
                    IF TransShipHead."Transfer Order Export" THEN BEGIN
                        WriteToGlbTextVar('RevReverseCharge', 'N', 0, TRUE);
                        WriteToGlbTextVar('Typ', 'EXPWP', 0, TRUE);
                    END ELSE
                        WriteToGlbTextVar('Typ', 'B2B', 0, TRUE);
                END;
        END;
        WriteToGlbTextVar('TaxPayerType', 'GST', 0, FALSE);
    end;

    local procedure WriteDocDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLInfo.Get(DtldGSTLedgEntry."Entry No.") then;
        IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::Invoice) AND
           ((DGLInfo."Sales Invoice Type" <> DGLInfo."Sales Invoice Type"::"Debit Note") AND
            (DGLInfo."Sales Invoice Type" <> DGLInfo."Sales Invoice Type"::Supplementary)) THEN
            WriteToGlbTextVar('DocTyp', 'INV', 0, TRUE)
        ELSE
            IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::"Credit Memo") THEN
                WriteToGlbTextVar('DocTyp', 'CRN', 0, TRUE)
            ELSE
                IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::Invoice) AND
              ((DGLInfo."Sales Invoice Type" = DGLInfo."Sales Invoice Type"::"Debit Note") OR
               (DGLInfo."Sales Invoice Type" = DGLInfo."Sales Invoice Type"::Supplementary)) THEN
                    WriteToGlbTextVar('DocTyp', 'DBN', 0, TRUE);

        WriteToGlbTextVar('DocNo', DtldGSTLedgEntry."Document No.", 0, TRUE);
        WriteToGlbTextVar('DocDate', FORMAT(DtldGSTLedgEntry."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>'), 0, TRUE);
        WriteToGlbTextVar('OrgInvNo', DGLInfo."Original Doc. No.", 0, FALSE);
    end;

    local procedure WriteSellerDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Location: Record 14;
        State: Record State;
    begin
        WriteToGlbTextVar('GstinNo', DtldGSTLedgEntry."Location  Reg. No.", 0, TRUE);
        Location.GET(DtldGSTLedgEntry."Location Code");
        WriteToGlbTextVar('LegalName', CompInfo.Name, 0, TRUE);
        WriteToGlbTextVar('TrdName', Location."Name 3", 0, TRUE);
        WriteToGlbTextVar('Address1', Location.Address, 0, TRUE);
        WriteToGlbTextVar('Address2', Location."Address 2", 0, TRUE);
        WriteToGlbTextVar('Location', Location.City, 0, TRUE);
        IF Location."Post Code" <> '' THEN
            WriteToGlbTextVar('Pincode', Location."Post Code", 1, TRUE)
        ELSE
            WriteToGlbTextVar('Pincode', '100000', 1, TRUE);
        State.GET(Location."State Code");
        WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
        WriteToGlbTextVar('MobileNo', 'null', 1, TRUE);

        IF Location."E-Mail" <> '' THEN
            WriteToGlbTextVar('EmailId', Location."E-Mail", 0, FALSE)
        ELSE
            WriteToGlbTextVar('EmailId', CompInfo."E-Mail", 0, FALSE);
    end;

    local procedure WriteBuyerDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Location: Record 14;
        Customer: Record 18;
        State: Record State;
        TransShipHdr: Record 5744;
        CustAdd: Text[100];
    begin

        TransShipHdr.RESET;
        TransShipHdr.SETRANGE(TransShipHdr."No.", DtldGSTLedgEntry."Document No.");
        IF TransShipHdr.FINDSET THEN
            IF NOT TransShipHdr."Transfer Order Export" THEN BEGIN
                WriteToGlbTextVar('GstinNo', DtldGSTLedgEntry."Buyer/Seller Reg. No.", 0, TRUE);
                Location.GET(TransShipHdr."Transfer-to Code");
                State.GET(Location."State Code");
                WriteToGlbTextVar('LegalName', CompInfo.Name, 0, TRUE);
                WriteToGlbTextVar('TrdName', Location."Name 3" + ' ,' + Location.Name, 0, TRUE);
                WriteToGlbTextVar('PlaceOfSupply', State."State Code (GST Reg. No.)", 0, TRUE);
                WriteToGlbTextVar('Address1', Location.Address, 0, TRUE);
                WriteToGlbTextVar('Address2', Location."Address 2", 0, TRUE);
                WriteToGlbTextVar('Location', Location.City, 0, TRUE);
                WriteToGlbTextVar('District', Location.City, 0, TRUE);
                IF Location."Post Code" <> '' THEN
                    WriteToGlbTextVar('Pincode', Location."Post Code", 1, TRUE)
                ELSE
                    WriteToGlbTextVar('Pincode', '100000', 1, TRUE);

                WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
                WriteToGlbTextVar('MobileNo', 'null', 1, TRUE);
            END ELSE BEGIN
                Customer.GET(TransShipHdr."To-Transaction Source Code");
                CustAdd := Customer.Address + ' ' + Customer."Address 2";
                WriteToGlbTextVar('GstinNo', 'URP', 0, TRUE);
                WriteToGlbTextVar('LegalName', Customer.Name, 0, TRUE);
                WriteToGlbTextVar('TrdName', Customer.Name, 0, TRUE);
                WriteToGlbTextVar('PlaceOfSupply', '96', 0, TRUE);
                WriteToGlbTextVar('Address1', Customer.Address, 0, TRUE);
                WriteToGlbTextVar('Address2', Customer."Address 2", 0, TRUE);
                WriteToGlbTextVar('Location', Customer.County, 0, TRUE);
                WriteToGlbTextVar('Pincode', '999999', 1, TRUE);
                WriteToGlbTextVar('StateCode', '96', 0, TRUE);
            END;
    end;


    local procedure WriteBuyersDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        State: Record State;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLEntryInfo: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLEntryInfo.get(DtldGSTLedgEntry."Entry No.") then;
        Customer.GET(DtldGSTLedgEntry."Source No.");
        CASE DGLEntryInfo."Original Doc. Type" OF
            DGLEntryInfo."Original Doc. Type"::Invoice:
                BEGIN
                    SalesInvoiceHeader.GET(DtldGSTLedgEntry."Document No.");
                    WriteToGlbTextVar('GstinNo', SalesInvoiceHeader."Customer GST Reg. No.", 0, TRUE);
                    State.GET(SalesInvoiceHeader."GST Bill-to State Code");
                    WriteToGlbTextVar('LegalName', SalesInvoiceHeader."Sell-to Customer Name", 0, TRUE);
                    WriteToGlbTextVar('PlaceOfSupply', State."State Code (GST Reg. No.)", 0, TRUE);
                    WriteToGlbTextVar('TrdName', SalesInvoiceHeader."Sell-to Customer Name", 0, TRUE);
                    WriteToGlbTextVar('Address1', SalesInvoiceHeader."Sell-to Address", 0, TRUE);
                    WriteToGlbTextVar('Address2', SalesInvoiceHeader."Sell-to Address 2", 0, TRUE);
                    WriteToGlbTextVar('Location', SalesInvoiceHeader."Sell-to City", 0, TRUE);
                    WriteToGlbTextVar('Pincode', SalesInvoiceHeader."Sell-to Post Code", 1, TRUE);
                    WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, false);
                END;
            DGLEntryInfo."Original Doc. Type"::"Credit Memo":
                BEGIN
                    SalesCrMemoHeader.GET(DtldGSTLedgEntry."Document No.");
                    WriteToGlbTextVar('GstinNo', SalesCrMemoHeader."Customer GST Reg. No.", 0, TRUE);
                    State.GET(SalesCrMemoHeader."GST Bill-to State Code");
                    WriteToGlbTextVar('LegalName', SalesCrMemoHeader."Sell-to Customer Name", 0, TRUE);
                    WriteToGlbTextVar('PlaceOfSupply', State."State Code (GST Reg. No.)", 0, TRUE);
                    WriteToGlbTextVar('TrdName', SalesCrMemoHeader."Sell-to Customer Name", 0, TRUE);
                    WriteToGlbTextVar('Address1', SalesCrMemoHeader."Sell-to Address", 0, TRUE);
                    WriteToGlbTextVar('Address2', SalesCrMemoHeader."Sell-to Address 2", 0, TRUE);
                    WriteToGlbTextVar('Location', SalesCrMemoHeader."Sell-to City", 0, TRUE);
                    WriteToGlbTextVar('Pincode', SalesCrMemoHeader."Sell-to Post Code", 1, TRUE);
                    WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, false);
                END;
        END;
    end;

    local procedure WriteBuyersNewDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        State: Record State;
        ShiptoAddress: Record 222;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLEntryInformation: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLEntryInformation.get(DtldGSTLedgEntry."Entry No.") then;
        Customer.GET(DtldGSTLedgEntry."Source No.");
        CASE DGLEntryInformation."Original Doc. Type" OF
            DGLEntryInformation."Original Doc. Type"::Invoice:
                BEGIN
                    SalesInvoiceHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesInvoiceHeader."Ship-to Code New");
                    WriteToGlbTextVar('GstinNo', ShiptoAddress."GST Registration No.", 0, TRUE);
                    State.GET(ShiptoAddress.State);
                    WriteToGlbTextVar('LegalName', ShiptoAddress.Name, 0, TRUE);
                    WriteToGlbTextVar('TrdName', ShiptoAddress.Name, 0, TRUE);
                    WriteToGlbTextVar('PlaceOfSupply', State."State Code (GST Reg. No.)", 0, TRUE);
                    WriteToGlbTextVar('Address1', ShiptoAddress.Address, 0, TRUE);
                    WriteToGlbTextVar('Address2', ShiptoAddress."Address 2", 0, TRUE);
                    WriteToGlbTextVar('Location', ShiptoAddress.City, 0, TRUE);
                    WriteToGlbTextVar('Pincode', ShiptoAddress."Post Code", 1, TRUE);
                    WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
                END;
            DGLEntryInformation."Original Doc. Type"::"Credit Memo":
                BEGIN
                    SalesCrMemoHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesCrMemoHeader."Ship-to Code New");
                    WriteToGlbTextVar('GstinNo', ShiptoAddress."GST Registration No.", 0, TRUE);
                    State.GET(ShiptoAddress.State);
                    WriteToGlbTextVar('LegalName', ShiptoAddress.Name, 0, TRUE);
                    WriteToGlbTextVar('TrdName', ShiptoAddress.Name, 0, TRUE);
                    WriteToGlbTextVar('PlaceOfSupply', State."State Code (GST Reg. No.)", 0, TRUE);
                    WriteToGlbTextVar('Address1', ShiptoAddress.Address, 0, TRUE);
                    WriteToGlbTextVar('Address2', ShiptoAddress."Address 2", 0, TRUE);
                    WriteToGlbTextVar('Location', ShiptoAddress.City, 0, TRUE);

                    WriteToGlbTextVar('Pincode', ShiptoAddress."Post Code", 1, TRUE);
                    WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
                END;
        END;
    end;

    local procedure WriteShipDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        State: Record State;
        ShiptoAddress: Record 222;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLEntryInforma: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLEntryInforma.get(DtldGSTLedgEntry."Entry No.") then;
        Customer.GET(DtldGSTLedgEntry."Source No.");
        CASE DGLEntryInforma."Original Doc. Type" OF
            DGLEntryInforma."Original Doc. Type"::Invoice:
                BEGIN
                    SalesInvoiceHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesInvoiceHeader."Ship-to Code");
                END;
            DGLEntryInforma."Original Doc. Type"::"Credit Memo":
                BEGIN
                    SalesCrMemoHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesCrMemoHeader."Ship-to Code");
                END;
        END;

        WriteToGlbTextVar('GstinNo', ShiptoAddress."GST Registration No.", 0, TRUE);
        State.GET(ShiptoAddress.State);
        WriteToGlbTextVar('LegalName', ShiptoAddress.Name, 0, TRUE);
        WriteToGlbTextVar('TrdName', ShiptoAddress.Name, 0, TRUE);
        WriteToGlbTextVar('Address1', ShiptoAddress.Address, 0, TRUE);
        WriteToGlbTextVar('Address2', ShiptoAddress."Address 2", 0, TRUE);
        WriteToGlbTextVar('Location', ShiptoAddress.City, 0, TRUE);
        IF ShiptoAddress."Post Code" <> '' THEN
            WriteToGlbTextVar('Pincode', ShiptoAddress."Post Code", 1, TRUE);
        WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
    end;

    local procedure WriteShipDtlsNew(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        State: Record State;
        ShiptoAddress: Record 222;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLInfor: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLInfor.get(DtldGSTLedgEntry."Entry No.") then;
        Customer.GET(DtldGSTLedgEntry."Source No.");
        CASE DGLInfor."Original Doc. Type" OF
            DGLInfor."Original Doc. Type"::Invoice:
                BEGIN
                    SalesInvoiceHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesInvoiceHeader."Ship-to Code New");
                END;
            DGLInfor."Original Doc. Type"::"Credit Memo":
                BEGIN
                    SalesCrMemoHeader.GET(DtldGSTLedgEntry."Document No.");
                    ShiptoAddress.GET(DtldGSTLedgEntry."Source No.", SalesCrMemoHeader."Ship-to Code New");
                END;
        END;

        WriteToGlbTextVar('GstinNo', ShiptoAddress."GST Registration No.", 0, TRUE);
        State.GET(ShiptoAddress.State);
        WriteToGlbTextVar('LegalName', ShiptoAddress.Name, 0, TRUE);
        WriteToGlbTextVar('TrdName', ShiptoAddress.Name, 0, TRUE);
        WriteToGlbTextVar('Address1', ShiptoAddress.Address, 0, TRUE);
        WriteToGlbTextVar('Address2', ShiptoAddress."Address 2", 0, TRUE);
        WriteToGlbTextVar('Location', ShiptoAddress.City, 0, TRUE);
        IF ShiptoAddress."Post Code" <> '' THEN
            WriteToGlbTextVar('Pincode', ShiptoAddress."Post Code", 1, TRUE);
        WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
    end;

    local procedure WriteValDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        AssVal: Decimal;
        CGSTVal: Decimal;
        SGSTVal: Decimal;
        IGSTVal: Decimal;
        CessVal: Decimal;
        CessNonAdVal: Decimal;
        TotalInvVal: Decimal;
        StCessVal: Decimal;
        PreviousLineNo: Integer;
        CustLedgerEntry: Record 21;
        DetaildGSTLedgerInfo: Record "Detailed GST Ledger Entry Info";
    begin
        if DetaildGSTLedgerInfo.Get(DtldGSTLedgEntry."Entry No.") then;
        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Entry Type", DtldGSTLedgEntry2."Entry Type"::"Initial Entry");
        //DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."GST %",DtldGSTLedgEntry."GST %");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                IF PreviousLineNo <> DtldGSTLedgEntry2."Document Line No." THEN
                    AssVal += ABS(DtldGSTLedgEntry2."GST Base Amount");
                PreviousLineNo := DtldGSTLedgEntry2."Document Line No.";
            UNTIL DtldGSTLedgEntry2.NEXT = 0;

        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document Type", DtldGSTLedgEntry."Document Type");
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                if DtldGSTLedgEntry2."GST Component Code" = 'CESS' then
                    CessVal += ABS(DtldGSTLedgEntry2."GST Amount")
                ELSE
                    if DtldGSTLedgEntry2."GST Component Code" = 'CGST' then
                        CGSTVal += ABS(DtldGSTLedgEntry2."GST Amount")
                    ELSE
                        if DtldGSTLedgEntry2."GST Component Code" = 'IGST' then
                            IGSTVal += ABS(DtldGSTLedgEntry2."GST Amount")
                        ELSE
                            if DtldGSTLedgEntry2."GST Component Code" = 'SGST' then
                                SGSTVal += ABS(DtldGSTLedgEntry2."GST Amount");
            UNTIL DtldGSTLedgEntry2.NEXT = 0;

        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE("Entry Type", DtldGSTLedgEntry2."Entry Type"::"Initial Entry");
        DtldGSTLedgEntry2.SETRANGE("Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry."Item Charge Entry" THEN BEGIN
            DtldGSTLedgEntry2.SETRANGE("Original Invoice No.", DtldGSTLedgEntry."Original Invoice No.");
            // 15800    DtldGSTLedgEntry2.SETRANGE("Item Charge Assgn. Line No.", DtldGSTLedgEntry."Item Charge Assgn. Line No.");
        END;
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                if DtldGSTLedgEntry2."GST Component Code" = 'CESS' then
                    CessNonAdVal += ABS(DtldGSTLedgEntry2."GST Amount");
            UNTIL DtldGSTLedgEntry2.NEXT = 0;
        StCessVal := CessNonAdVal;

        TotalInvVal := AssVal + CGSTVal + SGSTVal + IGSTVal + CessVal + CessNonAdVal + StCessVal;

        WriteToGlbTextVar('TotalTaxableVal', FORMAT(ABS(AssVal), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalSgstVal', FORMAT(ABS(SGSTVal), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalCgstVal', FORMAT(ABS(CGSTVal), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalIgstVal', FORMAT(ABS(IGSTVal), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalCesVal', FORMAT(ABS(CessVal), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalStateCesVal', FORMAT(ABS(StCessVal), 0, 2), 1, TRUE);

        CASE DetaildGSTLedgerInfo."Original Doc. Type" OF
            DetaildGSTLedgerInfo."Original Doc. Type"::Invoice:
                BEGIN
                    CustLedgerEntry.RESET;
                    CustLedgerEntry.SETAUTOCALCFIELDS("Original Amt. (LCY)");
                    CustLedgerEntry.SETRANGE("Document No.", DtldGSTLedgEntry."Document No.");
                    IF CustLedgerEntry.FINDFIRST THEN
                        TotalInvVal := CustLedgerEntry."Original Amt. (LCY)";
                    WriteToGlbTextVar('Discount', FORMAT(ABS(GetFreight(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.", 2)), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('OthCharge', FORMAT(GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.", 2), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('TotInvoiceVal', FORMAT(ABS(TotalInvVal), 0, 2), 1, FALSE);
                END;
            DetaildGSTLedgerInfo."Original Doc. Type"::"Credit Memo":
                BEGIN
                    CustLedgerEntry.RESET;
                    CustLedgerEntry.SETAUTOCALCFIELDS("Original Amt. (LCY)");
                    CustLedgerEntry.SETRANGE("Document No.", DtldGSTLedgEntry."Document No.");
                    IF CustLedgerEntry.FINDFIRST THEN
                        TotalInvVal := CustLedgerEntry."Original Amt. (LCY)";
                    WriteToGlbTextVar('Discount', FORMAT(ABS(GetFreight(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.", 3)), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('OthCharge', FORMAT(GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.", 3), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('TotInvoiceVal', FORMAT(ABS(TotalInvVal), 0, 2), 1, FALSE);
                END;
            DetaildGSTLedgerInfo."Original Doc. Type"::"Transfer Shipment":
                WriteToGlbTextVar('TotInvoiceVal', FORMAT(ABS(TotalInvVal), 0, 2), 1, FALSE);
        END;
    end;

    local procedure WriteItemList(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        DtldGSTLedgEntry3: Record "Detailed GST Ledger Entry";
        TaxProEInvoicingBuffer: Record 50013 temporary;
        Item: Record 27;
        UnitofMeasure: Record 204;
        "CGST%": Decimal;
        "SGST%": Decimal;
        "IGST%": Decimal;
        "CESS%": Decimal;
        TotalLines: Integer;
        LineCnt: Integer;
        "GST%": Decimal;
        GLAccount: Record 15;
        TCSAmt: Decimal;
        OthChgs: Decimal;
        SalesInvoiceLine: Record 113;
        SalesCrMemoLine: Record 115;
        TCSAmt_1: Decimal;
        updatetcsinfirstline: Boolean;
        FixedAsset: Record 5600;
        DetaildGSTLedgerInformation: Record "Detailed GST Ledger Entry Info";
        DGLInfoTransfer: Record "Detailed GST Ledger Entry Info";
    begin
        if DetaildGSTLedgerInformation.Get(DtldGSTLedgEntry."Entry No.") then;
        if DGLInfoTransfer.get(DtldGSTLedgEntry."Entry No.") then;
        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                IF NOT TaxProEInvoicingBuffer.GET(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.", DtldGSTLedgEntry2."Original Invoice No.", DetaildGSTLedgerInformation."Item Charge Assgn. Line No.") THEN BEGIN
                    TaxProEInvoicingBuffer.INIT;
                    TaxProEInvoicingBuffer."Document No." := DtldGSTLedgEntry2."Document No.";
                    TaxProEInvoicingBuffer."Document Line No." := DtldGSTLedgEntry2."Document Line No.";
                    TaxProEInvoicingBuffer."Original Invoice No." := DtldGSTLedgEntry2."Original Invoice No.";
                    TaxProEInvoicingBuffer."Item Charge Line No." := DetaildGSTLedgerInformation."Item Charge Assgn. Line No.";
                    TaxProEInvoicingBuffer.INSERT;
                END;
            UNTIL DtldGSTLedgEntry2.NEXT = 0;

        TaxProEInvoicingBuffer.RESET;
        TotalLines := TaxProEInvoicingBuffer.COUNT;
        // TCSAmt_1:=0;
        // //Get TCS Amount and then Divide Amount Based on
        // CASE DtldGSTLedgEntry2."Original Doc. Type" OF
        //        DtldGSTLedgEntry2."Original Doc. Type"::Invoice :
        //          BEGIN
        //             TCSAmt_1 := GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.",2);
        //          END;
        //        DtldGSTLedgEntry2."Original Doc. Type"::"Credit Memo" :
        //          BEGIN
        //             TCSAmt_1 := GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.",3);
        //          END;
        //  END;
        // updatetcsinfirstline:=FALSE;

        TaxProEInvoicingBuffer.RESET;
        IF TaxProEInvoicingBuffer.FINDSET THEN
            REPEAT
                LineCnt += 1;
                DtldGSTLedgEntry2.RESET;
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", TaxProEInvoicingBuffer."Document No.");
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document Line No.", TaxProEInvoicingBuffer."Document Line No.");
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Original Invoice No.", TaxProEInvoicingBuffer."Original Invoice No.");
                DetaildGSTLedgerInformation.SETRANGE(DetaildGSTLedgerInformation."Item Charge Assgn. Line No.", TaxProEInvoicingBuffer."Item Charge Line No."); // 15800
                IF DtldGSTLedgEntry2.FINDFIRST THEN BEGIN
                    GlbTextVar += '{';

                    WriteToGlbTextVar('SiNo', FORMAT(LineCnt), 0, TRUE);

                    IF DtldGSTLedgEntry2."GST Group Type" = DtldGSTLedgEntry2."GST Group Type"::Service THEN BEGIN
                        GLAccount.GET(DtldGSTLedgEntry2."No.");
                        WriteToGlbTextVar('ProductDesc', GLAccount.Name, 0, TRUE);
                        WriteToGlbTextVar('IsService', 'Y', 0, TRUE)
                    END ELSE BEGIN
                        IF DtldGSTLedgEntry2.Type = DtldGSTLedgEntry2.Type::Item THEN BEGIN
                            Item.GET(DtldGSTLedgEntry2."No.");
                            WriteToGlbTextVar('ProductDesc', Item.Description, 0, TRUE);
                            WriteToGlbTextVar('IsService', 'N', 0, TRUE);
                        END
                        ELSE
                            IF DtldGSTLedgEntry2.Type = DtldGSTLedgEntry2.Type::"G/L Account" THEN BEGIN
                                GLAccount.GET(DtldGSTLedgEntry2."No.");
                                WriteToGlbTextVar('ProductDesc', GLAccount.Name, 0, TRUE);
                                WriteToGlbTextVar('IsService', 'N', 0, TRUE)
                            END
                            ELSE
                                IF DtldGSTLedgEntry2.Type = DtldGSTLedgEntry2.Type::"Fixed Asset" THEN BEGIN
                                    FixedAsset.GET(DtldGSTLedgEntry2."No.");
                                    WriteToGlbTextVar('ProductDesc', FixedAsset.Description, 0, TRUE);
                                    WriteToGlbTextVar('IsService', 'N', 0, TRUE)
                                END;
                    END;

                    WriteToGlbTextVar('HsnCode', DtldGSTLedgEntry2."HSN/SAC Code", 0, TRUE);
                    WriteToGlbTextVar('BarCode', 'null', 1, TRUE);
                    WriteToGlbTextVar('Quantity', FORMAT(ABS(DtldGSTLedgEntry2.Quantity), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('FreeQuantity', '0', 1, TRUE);
                    UnitofMeasure.GET(DetaildGSTLedgerInformation.UOM);
                    WriteToGlbTextVar('Unit', UnitofMeasure."UOM For E Invoicing", 0, TRUE); // 15800 "GST Reporting UQC"
                    CASE DetaildGSTLedgerInformation."Original Doc. Type" OF
                        DetaildGSTLedgerInformation."Original Doc. Type"::Invoice:
                            WriteToGlbTextVar('UnitPrice', FORMAT(GetUnitPrice(DtldGSTLedgEntry2."Document No.", 2, DtldGSTLedgEntry2."Document Line No."), 0, 2), 1, TRUE);
                        DetaildGSTLedgerInformation."Original Doc. Type"::"Credit Memo":
                            WriteToGlbTextVar('UnitPrice', FORMAT(GetUnitPrice(DtldGSTLedgEntry2."Document No.", 3, DtldGSTLedgEntry2."Document Line No."), 0, 2), 1, TRUE);
                        DetaildGSTLedgerInformation."Original Doc. Type"::"Transfer Shipment":
                            WriteToGlbTextVar('UnitPrice', FORMAT(GetUnitPrice(DtldGSTLedgEntry2."Document No.", 4, DtldGSTLedgEntry2."Document Line No."), 0, 2), 1, TRUE);
                    END;

                    "GST%" := 0;
                    DtldGSTLedgEntry3.RESET;
                    DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document No.", DtldGSTLedgEntry2."Document No.");
                    DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document Line No.", DtldGSTLedgEntry2."Document Line No.");
                    IF DtldGSTLedgEntry3.FINDSET THEN
                        REPEAT
                            if DtldGSTLedgEntry3."GST Component Code" = 'CGST' then
                                "CGST%" := ABS(DtldGSTLedgEntry3."GST Amount")
                            ELSE
                                if DtldGSTLedgEntry3."GST Component Code" = 'SGST' then
                                    "SGST%" := ABS(DtldGSTLedgEntry3."GST Amount")
                                ELSE
                                    if DtldGSTLedgEntry3."GST Component Code" = 'IGST' then
                                        "IGST%" := ABS(DtldGSTLedgEntry3."GST Amount")
                                    ELSE
                                        if DtldGSTLedgEntry3."GST Component Code" = 'CESS' then
                                            "CESS%" := ABS(DtldGSTLedgEntry3."GST Amount");
                            "GST%" += DtldGSTLedgEntry3."GST %";
                        UNTIL DtldGSTLedgEntry3.NEXT = 0;
                    TCSAmt := 0;
                    IF DetaildGSTLedgerInformation.Get(DtldGSTLedgEntry2."Entry No.") then;
                    CASE DetaildGSTLedgerInformation."Original Doc. Type" OF
                        DetaildGSTLedgerInformation."Original Doc. Type"::Invoice:
                            BEGIN
                                TCSAmt := GetTCSAmount(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.", 2);//OthChrg
                                IF updatetcsinfirstline = FALSE THEN BEGIN
                                    //TCSAmt += GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.",2);
                                    TCSAmt += TCSAmt_1;
                                    updatetcsinfirstline := TRUE;
                                END;
                                WriteToGlbTextVar('TotAmount', FORMAT(GetTotalamount(2, DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.",
                                              DtldGSTLedgEntry2."Document Line No."), 0, 2), 1, TRUE);
                                SalesInvoiceLine.GET(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.");
                                WriteToGlbTextVar('Discount', FORMAT(ABS(SalesInvoiceLine."Line Discount Amount" +
                                                  GetStrucDisc(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.", 2, DtldGSTLedgEntry2."Document Line No.")), 0, 2), 1, TRUE);
                                WriteToGlbTextVar('OtherCharges', FORMAT(OthChgs + TCSAmt, 0, 2), 1, TRUE);
                            END;
                        DetaildGSTLedgerInformation."Original Doc. Type"::"Credit Memo":
                            BEGIN
                                TCSAmt := GetTCSAmount(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.", 3);//OthChrg
                                                                                                                                   //TCSAmt += GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.",3);
                                IF updatetcsinfirstline = FALSE THEN BEGIN
                                    //TCSAmt += GetTCSPayableGLAmt(DtldGSTLedgEntry2."Document No.",2);
                                    TCSAmt += TCSAmt_1;
                                    updatetcsinfirstline := TRUE;
                                END;
                                WriteToGlbTextVar('TotAmount', FORMAT(GetTotalamount(3, DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.",
                                              DtldGSTLedgEntry2."Document Line No."), 0, 2), 1, TRUE);
                                SalesCrMemoLine.GET(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.");
                                WriteToGlbTextVar('Discount', FORMAT(ABS(SalesCrMemoLine."Line Discount Amount" +
                                                        GetStrucDisc(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."No.", 2, DtldGSTLedgEntry2."Document Line No.")), 0, 2), 1, TRUE);
                                WriteToGlbTextVar('OtherCharges', FORMAT(OthChgs + TCSAmt, 0, 2), 1, TRUE);
                            END;
                        DGLInfoTransfer."Original Doc. Type"::"Transfer Shipment":
                            WriteToGlbTextVar('TotAmount', FORMAT(ABS(DtldGSTLedgEntry2."GST Base Amount") + GetDiscountAmount(DtldGSTLedgEntry2."Document No.",
                                            DtldGSTLedgEntry2."Document Line No.", DtldGSTLedgEntry2."Document Type".AsInteger()), 0, 2), 1, TRUE);
                    END;

                    WriteToGlbTextVar('AssAmount', FORMAT(ABS((DtldGSTLedgEntry2."GST Base Amount")), 0, 2), 1, TRUE);
                    WriteToGlbTextVar('GSTRate', FORMAT("GST%", 0, 2), 1, TRUE);
                    WriteToGlbTextVar('CgstAmt', FORMAT("CGST%", 0, 2), 1, TRUE);
                    WriteToGlbTextVar('SgstAmt', FORMAT("SGST%", 0, 2), 1, TRUE);
                    WriteToGlbTextVar('IgstAmt', FORMAT("IGST%", 0, 2), 1, TRUE);
                    WriteToGlbTextVar('CesRate', '0', 1, TRUE);
                    WriteToGlbTextVar('CesNonAdval', '0', 1, TRUE);
                    WriteToGlbTextVar('StateCes', '0', 1, TRUE);
                    WriteToGlbTextVar('TotItemVal', FORMAT(ABS(DtldGSTLedgEntry2."GST Base Amount") + "CGST%" + "SGST%" + "IGST%" + "CESS%" + OthChgs + TCSAmt, 0, 2), 1, TRUE);
                    GlbTextVar += '"BchDtls": {';
                    WriteToGlbTextVar('BatchName', 'null', 1, TRUE);
                    WriteToGlbTextVar('ExpiryDate', 'null', 1, TRUE);
                    WriteToGlbTextVar('WarrantyDate', 'null', 1, FALSE);
                    GlbTextVar += '}';
                    IF LineCnt <> TotalLines THEN
                        GlbTextVar += '},'
                    ELSE
                        GlbTextVar += '}'
                END;
            UNTIL TaxProEInvoicingBuffer.NEXT = 0;
    end;

    local procedure WriteToGlbTextVar(Label: Text; Value: Text; ValFormat: Option Text,Number; InsertComma: Boolean)
    var
        DoubleQuotes: Label '"';
        Comma: Label ',';
    begin
        IF Value <> '' THEN BEGIN
            IF ValFormat = ValFormat::Text THEN BEGIN
                IF InsertComma THEN
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + Value + DoubleQuotes + Comma
                ELSE
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + Value + DoubleQuotes;
            END ELSE BEGIN
                IF InsertComma THEN
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + Value + Comma
                ELSE
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + Value;
            END;
        END ELSE BEGIN
            IF ValFormat = ValFormat::Text THEN BEGIN
                IF InsertComma THEN
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + DoubleQuotes + Comma
                ELSE
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + DoubleQuotes;
            END ELSE BEGIN
                IF InsertComma THEN
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + '0' + DoubleQuotes + Comma
                ELSE
                    GlbTextVar += DoubleQuotes + Label + DoubleQuotes + ': ' + DoubleQuotes + '0' + DoubleQuotes;
            END;
        END;
    end;

    /*  local procedure CreateTempQRCode(var TempBlob: Record 99008535; RQRCode: Text)
     var
         SellerGSTIN: Text;
         BuyerGSTIN: Text;
         DocNo: Code[20];
         DocTyp: Text;
         DocDt: Text;
         IRNNo: Text;
         QRCodeInput: Text;
     begin
         QRCodeInput := RQRCode;
         CreateQRCode(QRCodeInput, TempBlob);
     end;

     local procedure CreateQRCode(QRCodeInput: Text; var TempBLOB: Record 99008535)
     var
         QRCodeFileName: Text[1024];
     begin
         CLEAR(TempBLOB);
         QRCodeFileName := GetQRCode(QRCodeInput);
         UploadFileBLOBImportandDeleteServerFile(TempBLOB, QRCodeFileName);
     end;

     local procedure GetQRCode(QRCodeInput: Text) QRCodeFileName: Text[1024]
     var
         [RunOnClient]
         IBarCodeProvider: DotNet IBarcodeProvider;
     begin
         GetBarCodeProvider(IBarCodeProvider);
         QRCodeFileName := IBarCodeProvider.GetBarcode(QRCodeInput);
     end;

     procedure GetBarCodeProvider(var IBarCodeProvider: DotNet QRCodeProvider)
     var
         [RunOnClient]
         QRCodeProvider: DotNet QRCodeProvider;
     begin
         IF ISNULL(IBarCodeProvider) THEN
             IBarCodeProvider := QRCodeProvider.QRCodeProvider;
     end;

     procedure UploadFileBLOBImportandDeleteServerFile(var TempBlob: Record "99008535"; FileName: Text[1024])
     var
         FileManagement: Codeunit "419";
     begin
         FileName := FileManagement.UploadFileSilent(FileName);
         FileManagement.BLOBImportFromServerFile(TempBlob, FileName);
         DeleteServerFile(FileName);
     end;

     local procedure DeleteServerFile(ServerFileName: Text)
     begin
         IF ERASE(ServerFileName) THEN; //QRCODE
     end;
  */ // 15800
    local procedure CheckIfCancelled(DocNo: Code[20])
    var
        TaxProOutput: Record 50014;
        AlreadyCancelErr: Label 'Invoice No. %1 is already cancelled, you cannot generate IRN no.';
    begin
        TaxProOutput.RESET;
        TaxProOutput.SETRANGE(TaxProOutput."Document No.", DocNo);
        IF TaxProOutput.FINDFIRST THEN
            IF TaxProOutput."Cancellation Date" <> '' THEN
                ERROR(AlreadyCancelErr, DocNo);
    end;

    local procedure GetDiscountAmount(DocNo: Code[20]; DocLineNo: Integer; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund): Decimal
    var
        SalesInvoiceLine: Record 113;
    begin
        CASE DocType OF
            DocType::Invoice:
                BEGIN
                    SalesInvoiceLine.RESET;
                    SalesInvoiceLine.SETRANGE("Document No.", DocNo);
                    SalesInvoiceLine.SETRANGE("Line No.", DocLineNo);
                    IF SalesInvoiceLine.FINDFIRST THEN
                        EXIT(SalesInvoiceLine."Line Discount Amount");
                END;
        END;
    end;

    /*  local procedure GetTotalDocValue(DocType: Integer; DocNo: Code[20])
     var
         SalesInvoiceHeader: Record 112;
         SalesCrMemoHeader: Record 114;
     begin
         CASE DocType OF
             //Sales Invoice
             2:
                 BEGIN
                     SalesInvoiceHeader.GET(DocNo);
                     SalesInvoiceHeader.CALCFIELDS(SalesInvoiceHeader."Amount to Customer");
                     TotalDocumentValue := SalesInvoiceHeader."Amount to Customer";
                 END;
             3:
                 BEGIN
                     SalesCrMemoHeader.GET(DocNo);
                     SalesCrMemoHeader.SETAUTOCALCFIELDS("Amount to Customer");
                     TotalDocumentValue := SalesCrMemoHeader."Amount to Customer";
                 END;
         END;
     end;
  */ // 15800 Not In Use
    local procedure GetTCSAmount(DocNo: Code[20]; DocLineNo: Integer; DocType: Integer): Decimal
    var
        SalesInvoiceLine: Record 113;
        SalesCrMemoLine: Record 115;
        TaxTranscValue: Record "Tax Transaction Value";
        TCSSetup: Record "TCS Setup";
    begin
        CASE DocType OF
            2:
                BEGIN
                    SalesInvoiceLine.SETRANGE("Document No.", DocNo);
                    SalesInvoiceLine.SETRANGE("Line No.", DocLineNo);
                    IF SalesInvoiceLine.FINDFIRST THEN begin
                        TCSSetup.Get();
                        TaxTranscValue.Reset();
                        TaxTranscValue.SetRange("Tax Record ID", SalesInvoiceLine.RecordId);
                        TaxTranscValue.SetRange("Line No. Filter", SalesInvoiceLine."Line No.");
                        TaxTranscValue.SetRange("Tax Type", TCSSetup."Tax Type");
                        TaxTranscValue.SetRange("Value Type", TaxTranscValue."Value Type"::COMPONENT);
                        TaxTranscValue.SetRange("Value ID", 6);
                        if TaxTranscValue.FindFirst() then
                            exit(TaxTranscValue.Amount);
                    end;
                END;
            3:
                BEGIN
                    SalesCrMemoLine.SETRANGE("Document No.", DocNo);
                    SalesCrMemoLine.SETRANGE("Line No.", DocLineNo);
                    IF SalesCrMemoLine.FINDFIRST THEN begin
                        TCSSetup.Get();
                        TaxTranscValue.Reset();
                        TaxTranscValue.SetRange("Tax Record ID", SalesCrMemoLine.RecordId);
                        TaxTranscValue.SetRange("Line No. Filter", SalesCrMemoLine."Line No.");
                        TaxTranscValue.SetRange("Tax Type", TCSSetup."Tax Type");
                        TaxTranscValue.SetRange("Value Type", TaxTranscValue."Value Type"::COMPONENT);
                        TaxTranscValue.SetRange("Value ID", 6);
                        if TaxTranscValue.FindFirst() then
                            exit(TaxTranscValue.Amount);
                    end;
                END;
        END;
    end;

    local procedure GetStrucDisc(DocNo: Code[20]; ItemCode: Code[20]; DocType: Integer; DocLineNo: Integer) DiscAmt: Decimal
    var
        PstdStrLineDtls: Record "Posted Str Order Line Details";
    begin
        PstdStrLineDtls.SETRANGE("Invoice No.", DocNo);
        PstdStrLineDtls.SETRANGE(Type, DocType);
        PstdStrLineDtls.SETRANGE("Item No.", ItemCode);
        PstdStrLineDtls.SETRANGE("Line No.", DocLineNo);
        PstdStrLineDtls.SETRANGE("Tax/Charge Type", PstdStrLineDtls."Tax/Charge Type"::Charges);
        PstdStrLineDtls.SETFILTER("Tax/Charge Group", '<>%1', 'FREIGHT');
        IF PstdStrLineDtls.FINDSET THEN
            REPEAT
                DiscAmt += PstdStrLineDtls."Amount (LCY)";
            UNTIL PstdStrLineDtls.NEXT = 0;

        EXIT(DiscAmt);
    end;

    local procedure GetFreight(DocNo: Code[20]; ItemCode: Code[20]; DocType: Integer) FreightAmt: Decimal
    var
        PstdStrLineDtls: Record "Posted Str Order Line Details";
    begin
        PstdStrLineDtls.SETRANGE("Invoice No.", DocNo);
        PstdStrLineDtls.SETRANGE("Tax/Charge Type", PstdStrLineDtls."Tax/Charge Type"::Charges);
        PstdStrLineDtls.SETRANGE("Tax/Charge Group", 'FREIGHT');
        IF PstdStrLineDtls.FINDSET THEN
            REPEAT
                FreightAmt += PstdStrLineDtls."Amount (LCY)";
            UNTIL PstdStrLineDtls.NEXT = 0;
        EXIT(FreightAmt);
    end;

    local procedure GetTotalamount(DocType: Integer; DocNo: Code[20]; ItemNo: Code[20]; DocLine: Integer): Decimal
    var
        SalesInvoiceLine: Record 113;
        SalesCrMemoLine: Record 115;
        TransferShipmentLine: Record 5745;
        TaxValue: Decimal;
    begin
        CASE DocType OF
            //Sales Invoice
            2:
                BEGIN
                    SalesInvoiceLine.SETRANGE("Document No.", DocNo);
                    SalesInvoiceLine.SETRANGE("No.", ItemNo);
                    SalesInvoiceLine.SETRANGE("Line No.", DocLine);
                    IF SalesInvoiceLine.FINDFIRST THEN
                        // EXIT(ROUND(SalesInvoiceLine.Quantity * SalesInvoiceLine."Unit Price",0.01));
                        EXIT(SalesInvoiceLine."Line Amount");
                END;
            3:
                BEGIN
                    SalesCrMemoLine.SETRANGE("Document No.", DocNo);
                    SalesCrMemoLine.SETRANGE("No.", ItemNo);
                    SalesCrMemoLine.SETRANGE("Line No.", DocLine);
                    IF SalesCrMemoLine.FINDFIRST THEN
                        EXIT(ROUND(SalesCrMemoLine.Quantity * SalesCrMemoLine."Unit Price", 0.01));
                END;
            8:
                BEGIN
                    TransferShipmentLine.SETRANGE("Document No.", DocNo);
                    TransferShipmentLine.SETFILTER(Quantity, '>%1', 0);
                    IF TransferShipmentLine.FINDSET THEN
                        REPEAT
                            TaxValue += ROUND(TransferShipmentLine.Amount);
                        UNTIL TransferShipmentLine.NEXT = 0;
                    EXIT(TaxValue);
                END;
        end;
    end;

    local procedure GetUnitPrice(DocNo: Code[20]; DocType: Integer; DocLineNo: Integer): Decimal
    var
        SalesInvoiceLine: Record 113;
        SalesCrMemoLine: Record 115;
        TransferShipmentLine: Record 5745;
    begin
        CASE DocType OF
            2://Invoice
                BEGIN
                    SalesInvoiceLine.SETRANGE("Document No.", DocNo);
                    SalesInvoiceLine.SETRANGE("Line No.", DocLineNo);
                    IF SalesInvoiceLine.FINDFIRST THEN
                        EXIT(ROUND(SalesInvoiceLine."Unit Price", 0.0001));
                END;
            3: //Credit Memo
                BEGIN
                    SalesCrMemoLine.SETRANGE("Document No.", DocNo);
                    SalesCrMemoLine.SETRANGE("Line No.", DocLineNo);
                    IF SalesCrMemoLine.FINDFIRST THEN
                        EXIT(ROUND(SalesCrMemoLine."Unit Price", 0.0001));
                END;
            4://Transfer
                BEGIN
                    TransferShipmentLine.SETRANGE("Document No.", DocNo);
                    TransferShipmentLine.SETRANGE("Line No.", DocLineNo);
                    IF TransferShipmentLine.FINDFIRST THEN
                        EXIT(ROUND(TransferShipmentLine."Unit Price", 0.001));
                END;
        END;
    end;

    local procedure GetTCSPayableGLAmt(DocNo: Code[20]; DocType: Integer): Decimal
    var
        SalesInvoiceLine: Record 113;
        SalesCrMemoLine: Record 115;
    begin
        CASE DocType OF
            2:
                BEGIN
                    SalesInvoiceLine.SETRANGE("Document No.", DocNo);
                    SalesInvoiceLine.SETRANGE("No.", '13-013435');
                    IF SalesInvoiceLine.FINDFIRST THEN
                        EXIT(SalesInvoiceLine."Line Amount");
                END;
            3:
                BEGIN
                    SalesCrMemoLine.SETRANGE("Document No.", DocNo);
                    SalesCrMemoLine.SETRANGE("No.", '13-013435');
                    IF SalesCrMemoLine.FINDFIRST THEN
                        EXIT(SalesCrMemoLine."Line Amount");
                END;
        END;
    end;

    local procedure GetDocType(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry"): Code[10]
    var
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        if DGLInfo.get(DtldGSTLedgEntry."Entry No.") then;
        IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::Invoice) AND
           ((DGLInfo."Sales Invoice Type" <> DGLInfo."Sales Invoice Type"::"Debit Note") AND
            (DGLInfo."Sales Invoice Type" <> DGLInfo."Sales Invoice Type"::Supplementary)) THEN
            EXIT('INV')
        ELSE
            IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::"Credit Memo") THEN
                EXIT('CRN')
            ELSE
                IF (DtldGSTLedgEntry."Document Type" = DtldGSTLedgEntry."Document Type"::Invoice) AND
              ((DGLInfo."Sales Invoice Type" = DGLInfo."Sales Invoice Type"::"Debit Note") OR
               (DGLInfo."Sales Invoice Type" = DGLInfo."Sales Invoice Type"::Supplementary)) THEN
                    EXIT('DBN');
    end;

    procedure GenerateDynamicsQR(DocNo: Code[20])
    var
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        AckNo: Code[20];
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        GSTRegistrationNos: Record "GST Registration Nos.";
        SalesInvoiceHeader: Record 112;
        BankAccount: Record 270;
        // 15800 B2CTempBlob: Record 99008535;
        // 15800 ROBOB2CQR: DotNet ROBO_B2C;
        PayLoad: Text;
        B2CMessageID: Text;
        B2CMessage: Text;
        B2CQRCode: Text;
        Imaget: Boolean;
        CustomerLedentry: Record "Cust. Ledger Entry";
        AmttoCustomer: Decimal;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        Location: Record Location;
        Base64: Codeunit "Base64 Convert";
        instm: InStream;
        Outstrm: OutStream;
    begin
        EInvoiceSetUp.Get();
        CustomerLedentry.Reset();
        CustomerLedentry.SetAutoCalcFields("Amount (LCY)");
        CustomerLedentry.SetRange("Document No.", DocNo);
        if CustomerLedentry.FindFirst() then
            AmttoCustomer := CustomerLedentry."Amount (LCY)";
        //6587 ++

        CompInfo.GET;
        BankAccount.GET(CompInfo."B2C QR Bank No.");
        SalesInvoiceHeader.GET(DocNo);
        //SalesInvoiceHeader.CALCFIELDS("Amount to Customer");
        IF SalesInvoiceHeader."GST Customer Type" <> SalesInvoiceHeader."GST Customer Type"::Unregistered THEN
            ERROR('Cannot generate QR code for other supply type, except B2C');
        Location.Get(SalesInvoiceHeader."Location Code");
        ROBOSetup.GET(SalesInvoiceHeader."Location GST Reg. No.");
        CLEAR(GlbTextVar);
        GlbTextVar += '{';
        WriteToGlbTextVar('payeeVPA', FORMAT(BankAccount."Payee VPA"), 0, TRUE);
        WriteToGlbTextVar('payeeName', BankAccount.Name, 0, TRUE);
        WriteToGlbTextVar('payeeTransrefid', SalesInvoiceHeader."No." + '-' + SalesInvoiceHeader."Bill-to Customer No." + '-' +
                          SalesInvoiceHeader."Bill-to Name", 0, TRUE);
        WriteToGlbTextVar('payeeTransnote', SalesInvoiceHeader."No." + ',' + SalesInvoiceHeader."Bill-to Customer No.", 0, TRUE);
        IF SalesInvoiceHeader."Currency Factor" = 0 THEN
            WriteToGlbTextVar('payeeAmount', FORMAT(AmttoCustomer, 0, 2), 0, TRUE) // SalesInvoiceHeader."Amount to Customer"
        ELSE
            WriteToGlbTextVar('payeeAmount', FORMAT(AmttoCustomer / SalesInvoiceHeader."Currency Factor", 0, 2), 0, TRUE); // SalesInvoiceHeader."Amount to Customer"
        WriteToGlbTextVar('payeeCurrencyCode', 'INR', 0, TRUE);
        WriteToGlbTextVar('suppliergstn', SalesInvoiceHeader."Location GST Reg. No.", 0, TRUE);
        WriteToGlbTextVar('supplierUPIId', BankAccount."Supplier UPI ID", 0, TRUE);
        WriteToGlbTextVar('payeeBankAccNum', BankAccount."Bank Account No.", 0, TRUE);
        WriteToGlbTextVar('payeeBankIfsc', BankAccount."IFSC Code", 0, TRUE);
        WriteToGlbTextVar('docNo', SalesInvoiceHeader."No.", 0, TRUE);
        WriteToGlbTextVar('docDt', FORMAT(SalesInvoiceHeader."Posting Date"), 0, TRUE);
        GetGSTAmtB2QC(SalesInvoiceHeader."No.", 0, FALSE);
        WriteToGlbTextVar('cgst', FORMAT(ABS(GSTAmt[1]), 0, 2), 0, TRUE);
        WriteToGlbTextVar('sgst', FORMAT(ABS(GSTAmt[2]), 0, 2), 0, TRUE);
        WriteToGlbTextVar('igst', FORMAT(ABS(GSTAmt[3]), 0, 2), 0, TRUE);
        WriteToGlbTextVar('cess', '0', 0, TRUE);
        WriteToGlbTextVar('gst', FORMAT(ABS(GSTAmt[1] + GSTAmt[2] + GSTAmt[3]), 0, 2), 0, FALSE);
        GlbTextVar += '}';

        MESSAGE(GlbTextVar);
        EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', ROBOSetup."E-Invoice User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."Dynamics QR URL");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            Message(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                B2CMessageID := JResultToken.AsValue().AsText();
            if JResultToken.AsValue().AsInteger() = 1 then begin
                //if JResultObject.Get('Message', JResultToken) then
                //B2CMessage := JResultToken.AsValue().AsText();
                //Message(Format(JResultToken));
            end else
                if JResultObject.Get('Message', JResultToken) then
                    //Message(Format(JResultToken));
                    B2CMessage := JResultToken.AsValue().AsText();
            if JResultObject.Get('Status', JResultToken) then
                ReturnMessage := JResultToken.AsValue().AsText();
            if JResultObject.Get('Data', JResultToken) then
                if JResultToken.IsObject then begin
                    JResultToken.WriteTo(OutputMessage);
                    JOutputObject.ReadFrom(OutputMessage);
                    if JOutputObject.Get('QRCode', JOutputToken) then
                        QRText := JOutputToken.AsValue().AsText();
                end;
        end;

        /*
        //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
        ROBOB2CQR.B2CQRCode(GlbTextVar,ROBOSetup.client_id,ROBOSetup.client_secret,ROBOSetup.IPAddress,
                          ROBOSetup.user_name,ROBOSetup.Gstin,ROBOSetup."Error File Save Path",
                          ROBOSetup."Dynamics QR URL",B2CMessageID,B2CMessage,B2CQRCode);
        //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
        IF B2CMessageID = '1' THEN BEGIN
            SalesInvoiceHeader."B2C QR Code".CreateOutStream(Outstrm);
            Base64.FromBase64(QRText, Outstrm);
            Imaget := TRUE;
            MESSAGE(ReturnMessage, B2CMessage);
            SalesInvoiceHeader.Modify();
        END ELSE
            MESSAGE(ReturnMessage, B2CMessage);

    end;

    local procedure GetGSTAmtB2QC(DocNo: Code[20]; DocLineNo: Integer; ItemCharge: Boolean) "GST%": Decimal
    var
        DtldGSTLedgEntry3: Record "Detailed GST Ledger Entry";
    // 15800 GSTComponent: Record 16405;
    begin
        //6587 ++
        CLEAR(GSTAmt);
        DtldGSTLedgEntry3.RESET;
        DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document No.", DocNo);
        DtldGSTLedgEntry3.SETRANGE("Entry Type", DtldGSTLedgEntry3."Entry Type"::"Initial Entry");
        IF DtldGSTLedgEntry3.FINDSET THEN
            REPEAT
                if DtldGSTLedgEntry3."GST Component Code" = 'CGST' then
                    GSTAmt[1] += DtldGSTLedgEntry3."GST Amount";
                if DtldGSTLedgEntry3."GST Component Code" = 'SGST' then
                    GSTAmt[2] += DtldGSTLedgEntry3."GST Amount";
                if DtldGSTLedgEntry3."GST Component Code" = 'IGST' then
                    GSTAmt[3] += DtldGSTLedgEntry3."GST Amount";
            UNTIL DtldGSTLedgEntry3.NEXT = 0;
        //6587 --
    end;


    procedure GenerateTrShipEinv(TrShip_From: Record 5744)
    var
        Location: Record 14;
        Customer: Record 18;
        State: Record State;
        TrShipLine: Record 5745;
        Item: Record 27;
        UnitofMeasure: Record 204;
        TaxProOutput: Record 50014;
        LineCnt: Integer;
        TotalLines: Integer;
        RetVal: Text;
        IRNText: Text;
        AckNo: Text;
        AckDt: Text;
        DigitalSign: Text;
        QRCode: Text;
        DigitalSignBstr: BigText;
        QRCodeBstr: BigText;
        oStream: OutStream;
        GSTINNo: Code[20];
        IRNStatus: Text;
        RQRCode: Text;
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        DayCode: Integer;
        AckDateText: Text;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        OutSrm: OutStream;
        GSTRegistrationNos: Record "GST Registration Nos.";
        Contries: Record "Country/Region";
    begin
        EInvoiceSetUp.Get();
        IF (TrShip_From."Transaction Type" <> 'LUT-1') THEN
            ERROR('Transaction should be LUT for generating E-Invoice');

        Location.GET(TrShip_From."Transfer-from Code");

        GSTINNo := Location."GST Registration No.";

        Authenticate(GSTINNo);
        CompInfo.GET;
        GlbTextVar := '';
        //Write Common Details
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'INVOICE', 0, TRUE);
        WriteToGlbTextVar('Version', '1.1', 0, TRUE);
        WriteToGlbTextVar('Irn', '', 0, TRUE);


        //Write TpApiTranDtls
        GlbTextVar += '"TpApiTranDtls": {';
        WriteToGlbTextVar('RevReverseCharge', 'N', 0, TRUE);
        WriteToGlbTextVar('Typ', 'EXPWOP', 0, TRUE);
        WriteToGlbTextVar('TaxPayerType', 'GST', 0, FALSE);
        GlbTextVar += '},';

        //Write TpApiDocDtls
        GlbTextVar += '"TpApiDocDtls": {';
        WriteToGlbTextVar('DocTyp', 'INV', 0, TRUE);
        WriteToGlbTextVar('DocNo', TrShip_From."No.", 0, TRUE);
        WriteToGlbTextVar('DocDate', FORMAT(TrShip_From."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>'), 0, TRUE);
        WriteToGlbTextVar('OrgInvNo', TrShip_From."No.", 0, FALSE);
        GlbTextVar += '},';

        //Write SellerDtls
        GlbTextVar += '"TpApiSellerDtls": {';
        WriteToGlbTextVar('GstinNo', GSTINNo, 0, TRUE);
        WriteToGlbTextVar('LegalName', CompInfo.Name, 0, TRUE);
        WriteToGlbTextVar('TrdName', Location."Name 3", 0, TRUE);
        WriteToGlbTextVar('Address1', Location.Address, 0, TRUE);
        WriteToGlbTextVar('Address2', Location."Address 2", 0, TRUE);
        WriteToGlbTextVar('Location', Location.City, 0, TRUE);
        WriteToGlbTextVar('Pincode', Location."Post Code", 1, TRUE);
        State.GET(Location."State Code");
        WriteToGlbTextVar('StateCode', State."State Code (GST Reg. No.)", 0, TRUE);
        WriteToGlbTextVar('MobileNo', 'null', 1, FALSE);
        GlbTextVar += '},';

        //Write BuyerDtls
        GlbTextVar += '"TpApiBuyerDtls": {';
        Customer.GET(TrShip_From."To-Transaction Source Code");
        WriteToGlbTextVar('GstinNo', 'URP', 0, TRUE);
        WriteToGlbTextVar('LegalName', Customer.Name, 0, TRUE);
        WriteToGlbTextVar('TrdName', Customer.Name, 0, TRUE);
        WriteToGlbTextVar('PlaceOfSupply', '96', 0, TRUE);
        WriteToGlbTextVar('Address1', Customer.Address, 0, TRUE);
        WriteToGlbTextVar('Location', Customer.County, 0, TRUE);
        WriteToGlbTextVar('Pincode', '999999', 1, TRUE);
        WriteToGlbTextVar('StateCode', '96', 0, false);
        GlbTextVar += '},';

        //Write Export Details
        if Contries.Get(Customer."Country/Region Code") then;
        GlbTextVar += '"TpApiExpDtls": {';
        WriteToGlbTextVar('CountryCode', Contries."Country Code for E-Invoicing", 0, false);
        GlbTextVar += '},';




        //Write ValDtls
        GlbTextVar += '"TpApiValDtls": {';
        WriteToGlbTextVar('TotalTaxableVal', FORMAT(GetTotalamount(8, TrShip_From."No.", '', 0), 0, 2), 1, TRUE);
        WriteToGlbTextVar('TotalSgstVal', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('TotalCgstVal', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('TotalIgstVal', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('TotalCesVal', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('TotalStateCesVal', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('TotInvoiceVal', FORMAT(GetTotalamount(8, TrShip_From."No.", '', 0), 0, 2), 1, FALSE);
        GlbTextVar += '},';


        //Write ItemList
        GlbTextVar += '"TpApiItemList": [';
        TrShipLine.RESET;
        TrShipLine.SETRANGE("Document No.", TrShip_From."No.");
        TrShipLine.SETFILTER(Quantity, '>%1', 0);
        IF TrShipLine.FINDSET THEN BEGIN
            TotalLines := TrShipLine.COUNT;
            REPEAT
                LineCnt += 1;
                GlbTextVar += '{';
                WriteToGlbTextVar('SiNo', FORMAT(LineCnt), 0, TRUE);
                Item.GET(TrShipLine."Item No.");
                WriteToGlbTextVar('ProductDesc', Item.Description, 0, TRUE);
                WriteToGlbTextVar('IsService', 'N', 0, TRUE);
                WriteToGlbTextVar('HsnCode', TrShipLine."HSN/SAC Code", 0, TRUE);
                WriteToGlbTextVar('Quantity', FORMAT(ABS(TrShipLine.Quantity), 0, 2), 1, TRUE);
                UnitofMeasure.GET(TrShipLine."Unit of Measure Code");
                WriteToGlbTextVar('Unit', UnitofMeasure."UOM For E Invoicing", 0, TRUE); // 15800 UnitofMeasure."GST Reporting UQC" Replaced by
                WriteToGlbTextVar('UnitPrice', FORMAT(TrShipLine."Unit Price", 0, 2), 1, TRUE);
                WriteToGlbTextVar('TotAmount', FORMAT(TrShipLine.Amount, 0, 2), 1, TRUE);
                WriteToGlbTextVar('AssAmount', FORMAT(TrShipLine.Amount, 0, 2), 1, TRUE);
                WriteToGlbTextVar('GSTRate', FORMAT(0), 1, TRUE);
                WriteToGlbTextVar('CgstAmt', FORMAT(0), 1, TRUE);
                WriteToGlbTextVar('SgstAmt', FORMAT(0), 1, TRUE);
                WriteToGlbTextVar('IgstAmt', FORMAT(0), 1, TRUE);
                WriteToGlbTextVar('CesRate', '0', 1, TRUE);
                WriteToGlbTextVar('CesNonAdval', '0', 1, TRUE);
                WriteToGlbTextVar('StateCes', '0', 1, TRUE);
                WriteToGlbTextVar('TotItemVal', FORMAT(TrShipLine.Amount, 0, 2), 1, false);
                IF LineCnt <> TotalLines THEN
                    GlbTextVar += '},'
                ELSE
                    GlbTextVar += '}'
            UNTIL TrShipLine.NEXT = 0;
        END;
        GlbTextVar += ']';
        GlbTextVar += '}';

        MESSAGE(GlbTextVar);
        GSTRegistrationNos.GET(Location."GST Registration No.");
        EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."E-Invoice User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            Char13 := 13;
            Char10 := 10;
            NewLine := FORMAT(Char10) + FORMAT(Char13);
            ErrorLogMessage += NewLine + 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
      + ResultMessage + NewLine + '-----------------------------------------------------------';

            if JResultObject.Get('MessageId', JResultToken) then
                MessageID := JResultToken.AsValue().AsText();
            if JResultToken.AsValue().AsInteger() = 1 then begin
                if JResultObject.Get('Message', JResultToken) then;
                //Message(Format(JResultToken));
            end else
                if JResultObject.Get('Message', JResultToken) then
                    //Message(Format(JResultToken));
                    ReturnMessage := JResultToken.AsValue().AsText();

            if JResultObject.Get('Data', JResultToken) then
                if JResultToken.IsObject then begin
                    JResultToken.WriteTo(OutputMessage);
                    JOutputObject.ReadFrom(OutputMessage);
                    if JOutputObject.Get('AckDt', JOutputToken) then
                        AckDateText := JOutputToken.AsValue().AsText();
                    Evaluate(YearCode, CopyStr(AckDateText, 1, 4));
                    Evaluate(MonthCode, CopyStr(AckDateText, 6, 2));
                    Evaluate(DayCode, CopyStr(AckDateText, 9, 2));
                    Evaluate(AckDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(AckDateText, 12, 8));
                    if JOutputObject.Get('Irn', JOutputToken) then
                        IRNText := JOutputToken.AsValue().AsText();
                    if JOutputObject.Get('SignedQRCode', JOutputToken) then
                        QRText := JOutputToken.AsValue().AsText();
                    if JOutputObject.Get('AckNo', JOutputToken) then
                        AckNo := JOutputToken.AsValue().AsCode();
                    if JOutputObject.Get('Status', JOutputToken) then
                        IRNStatus := JOutputToken.AsValue().AsText();
                end;
        end;

        /*ROBOSetup.GET(Location."GST Registration No.");
        ROBOSetup.TESTFIELD(ROBOSetup.client_id);
        ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
        ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
        ROBOSetup.TESTFIELD(ROBOSetup.user_name);
        ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
        ROBOSetup.TESTFIELD(ROBOSetup.Password);

        RetVal := ROBODLL.GenerateIRN(GlbTextVar,
                                      ROBOSetup.client_id,
                                      ROBOSetup.client_secret,
                                      ROBOSetup.IPAddress,
                                      ROBOSetup.user_name,
                                      ROBOSetup.Gstin,
                                      ROBOSetup."Error File Save Path",
                                      IRNText,
                                      RQRCode,
                                      AckNo,
                                      AckDt,
                                      IRNStatus,
                                      MessageID,
                                      ReturnMessage,
                                      ROBOSetup."URL E-Inv");*/ // 15800 

        TaxProOutput.INIT;
        TaxProOutput."Document Type" := TaxProOutput."Document Type"::"Transfer Shipment";
        TaxProOutput."Document No." := TrShip_From."No.";
        TaxProOutput."IRN No." := IRNText;
        TaxProOutput."Ack Nos" := AckNo;
        TaxProOutput."Ack Date" := Format(AckDate);
        TaxProOutput."IRN Status" := IRNStatus;
        TaxProOutput."Message Id" := MessageID;

        IF QRCodeBstr.LENGTH > 0 THEN BEGIN
            TaxProOutput."QR Code".CREATEOUTSTREAM(oStream);
            QRCodeBstr.WRITE(oStream);
        END;
        IF DigitalSignBstr.LENGTH > 0 THEN BEGIN
            TaxProOutput."Digital Signature".CREATEOUTSTREAM(oStream);
            DigitalSignBstr.WRITE(oStream);
        END;
        if QRText = '' then begin
            Clear(TaxProOutput."QR Code Temp");
        end;
        TaxProOutput.JSON.CreateOutStream(OutSrm);
        OutSrm.WriteText(GlbTextVar);
        TaxProOutput."Output Payload E-Invoice".CreateOutStream(StoreOutStrm);
        StoreOutStrm.WriteText(ErrorLogMessage);

        IF MessageID = '1' THEN BEGIN
            MESSAGE(IRNMsg);
        END ELSE
            MESSAGE(ReturnMessage);
        IF NOT TaxProOutput.INSERT THEN
            TaxProOutput.MODIFY;

        Clear(RecRef);
        RecRef.Get(TaxProOutput.RecordId);
        if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
            if TempBlob.HasValue() then begin
                FldRef := RecRef.Field(TaxProOutput.FieldNo("QR Code Temp"));
                TempBlob.ToRecordRef(RecRef, TaxProOutput.FieldNo("QR Code Temp"));
                RecRef.Modify();
            end;
        END;
    end;


    local procedure WriteDispatchDtls(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        Customer: Record 18;
        State: Record State;
        SalesInvoiceHeader: Record 112;
        SalesCrMemoHeader: Record 114;
        DGLEntryInfo: Record "Detailed GST Ledger Entry Info";
        AlternateAddress: Record "Alternative Address";
        CompanyInfo: Record "Company Information";
        StateIn: Record State;
        TransferShipmentHeader: Record "Transfer Shipment Header";
    begin
        CompanyInfo.get();
        if DGLEntryInfo.get(DtldGSTLedgEntry."Entry No.") then;
        CASE DGLEntryInfo."Original Doc. Type" OF
            DGLEntryInfo."Original Doc. Type"::Invoice:
                BEGIN
                    SalesInvoiceHeader.GET(DtldGSTLedgEntry."Document No.");
                    AlternateAddress.Reset();// 15800 
                    AlternateAddress.SetRange("Employee No.", 'PIPL');
                    AlternateAddress.SetRange(Code, SalesInvoiceHeader.Alternative);
                    if AlternateAddress.FindFirst() then begin
                        WriteToGlbTextVar('CompName', AlternateAddress.Name, 0, TRUE);
                        State.GET(SalesInvoiceHeader."GST Bill-to State Code");
                        WriteToGlbTextVar('Address1', AlternateAddress.Address, 0, TRUE);
                        WriteToGlbTextVar('Address2', AlternateAddress."Address 2", 0, TRUE);
                        WriteToGlbTextVar('Location', AlternateAddress.City, 0, TRUE);
                        WriteToGlbTextVar('Pincode', AlternateAddress."Post Code", 1, TRUE);
                        if StateIn.Get(AlternateAddress.EIN_State) then;
                        WriteToGlbTextVar('StateCode', StateIn."State Code for E-Invoicing", 0, false);
                    end;
                END;
            DGLEntryInfo."Original Doc. Type"::"Transfer Shipment":
                begin
                    TransferShipmentHeader.GET(DtldGSTLedgEntry."Document No.");
                    AlternateAddress.Reset();
                    AlternateAddress.SetRange("Employee No.", 'PIPL');
                    AlternateAddress.SetRange(Code, TransferShipmentHeader.Alternative);
                    if AlternateAddress.FindFirst() then begin
                        WriteToGlbTextVar('CompName', AlternateAddress.Name, 0, TRUE);
                        WriteToGlbTextVar('Address1', AlternateAddress.Address, 0, TRUE);
                        WriteToGlbTextVar('Address2', AlternateAddress."Address 2", 0, TRUE);
                        WriteToGlbTextVar('Location', AlternateAddress.City, 0, TRUE);
                        WriteToGlbTextVar('Pincode', AlternateAddress."Post Code", 1, TRUE);
                        if StateIn.Get(AlternateAddress.EIN_State) then;
                        WriteToGlbTextVar('StateCode', StateIn."State Code for E-Invoicing", 0, false);
                    end;
                end;



        END;
    end;



}
