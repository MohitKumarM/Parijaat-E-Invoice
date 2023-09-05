codeunit 50400 "Generate EwaySalesInvoiceCloud"
{
    trigger OnRun()
    begin
    end;

    var
        StoreOutStrm: OutStream;

        Char10: Char;
        Char13: Char;
        NewLine: Text;
        ErrorLogMessage: Text;

        CompInfo: Record 79;
        ROBOSetup: Record "GST Registration Nos.";
        GlbTextVar: Text;
        EwayBillNoErr: Label 'Eway Bill No. has not been generated. Update Part A to generate Eway bill first.';

    procedure GenerateInvoiceDetails(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SalesInvoiceHeader: Record 112;
        State: Record State;
        Country: Record 9;
        Location: Record 14;
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        ROBOOutput: Record "E-Invoice Output";
        CessVal: Decimal;
        CGSTVal: Decimal;
        IGSTVal: Decimal;
        AlternativeAdrees: Record "Alternative Address";
        SGSTVal: Decimal;
        CessNonAdVal: Decimal;
        StCessVal: Decimal;
        TotalInvVal: Decimal;
        AssVal: Decimal;
        PreviousLineNo: Integer;
        Remarks: Text;
        Status: Text;
        Transporter: Record 23;
        Customer: Record 18;
        ReturnMsg: Label 'Status : %1\ %2';
        SalesAdd: Text[100];
        DetailedGSTLedgerInfo: Record "Detailed GST Ledger Entry Info";
        LocAdd: Text[100];
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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        GSTRegistrationNos: Record "GST Registration Nos.";
        JResultArray: JsonArray;
        TotalInvoiceAmt: Decimal;
        TotaInvoiceValueCheck: Decimal;
        SalesInvLine: Record "Sales Invoice Line";
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");
        SalesInvoiceHeader.GET(DocNo);
        Customer.GET(SalesInvoiceHeader."Sell-to Customer No.");
        CLEAR(CessVal);
        CLEAR(CGSTVal);
        CLEAR(IGSTVal);
        CLEAR(SGSTVal);
        CLEAR(CessNonAdVal);
        CLEAR(StCessVal);
        CLEAR(TotalInvVal);
        CLEAR(AssVal);
        CLEAR(PreviousLineNo);

        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            GlbTextVar := '';
            //Write Common Details
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'INVOICE', 0, TRUE);

            GlbTextVar += '"data" : [';
            GlbTextVar += '{';
            // 15800 Open For Production    WriteToGlbTextVar('GENERATOR_GSTIN', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
            WriteToGlbTextVar('GENERATOR_GSTIN', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
            WriteToGlbTextVar('TRANSACTION_TYPE', 'Outward', 0, TRUE);
            CASE SalesInvoiceHeader."Invoice Type" OF
                SalesInvoiceHeader."Invoice Type"::" ",
              SalesInvoiceHeader."Invoice Type"::Taxable,
              SalesInvoiceHeader."Invoice Type"::Supplementary:
                    WriteToGlbTextVar('TRANSACTION_SUB_TYPE', 'Supply', 0, TRUE);

                SalesInvoiceHeader."Invoice Type"::Export:
                    WriteToGlbTextVar('TRANSACTION_SUB_TYPE', 'Export', 0, TRUE);
            END;

            WriteToGlbTextVar('SUPPLY_TYPE', '', 0, TRUE); // Regular 

            IF SalesInvoiceHeader."Invoice Type" IN [SalesInvoiceHeader."Invoice Type"::"Bill of Supply"] THEN
                WriteToGlbTextVar('DOC_TYPE', 'Bill of Supply', 0, TRUE)
            ELSE
                WriteToGlbTextVar('DOC_TYPE', 'Tax Invoice', 0, TRUE);

            WriteToGlbTextVar('DOC_NO', FORMAT(SalesInvoiceHeader."No."), 0, TRUE);
            WriteToGlbTextVar('DOC_DATE', FORMAT(SalesInvoiceHeader."Document Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
            // 15800 Open For Production WriteToGlbTextVar('CONSIGNOR_GSTIN_NO', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
            WriteToGlbTextVar('CONSIGNOR_GSTIN_NO', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
            WriteToGlbTextVar('CONSIGNOR_LEGAL_NAME', CompInfo.Name, 0, TRUE);
            // ********* 15800 ForUAT
            SalesInvLine.Reset();
            SalesInvLine.SetRange("Document No.", SalesInvoiceHeader."No.");
            if SalesInvLine.FindFirst() then;
            if SalesInvLine."GST Jurisdiction Type" = SalesInvLine."GST Jurisdiction Type"::Intrastate then
                WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', '05AAACE1378A1Z9', 0, TRUE) // Test For UAT
            else
                WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', '05AAACE3061A1ZH', 0, TRUE); // Test For UAT
                                                                                     // ********* 15800 ForUAT
                                                                                     // 15800 Open For Production WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', DtldGSTLedgerEntry."Buyer/Seller Reg. No.", 0, TRUE);

            WriteToGlbTextVar('CONSIGNEE_LEGAL_NAME', SalesInvoiceHeader."Ship-to Name", 0, TRUE);
            SalesAdd := SalesInvoiceHeader."Ship-to Address" + ' ,' + SalesInvoiceHeader."Ship-to Address 2";
            WriteToGlbTextVar('SHIP_ADDRESS_LINE1', SalesAdd, 0, TRUE);

            if DetailedGSTLedgerInfo.Get(DtldGSTLedgerEntry."Entry No.") then
                IF State.GET(DetailedGSTLedgerInfo."Shipping Address State Code") THEN
                    // 15800 Open For Production WriteToGlbTextVar('SHIP_STATE', State.Description, 0, TRUE) 
                    if SalesInvLine."GST Jurisdiction Type" = SalesInvLine."GST Jurisdiction Type"::Intrastate then
                        WriteToGlbTextVar('SHIP_STATE', 'Haryana', 0, TRUE) // // Test For UAT
                    else
                        WriteToGlbTextVar('SHIP_STATE', 'Delhi', 0, TRUE)// Test For UAT
                ELSE BEGIN
                    State.GET(Customer."State Code");
                    // 15800 Open For Production WriteToGlbTextVar('SHIP_STATE', State.Description, 0, TRUE)
                    if SalesInvLine."GST Jurisdiction Type" = SalesInvLine."GST Jurisdiction Type"::Intrastate then
                        WriteToGlbTextVar('SHIP_STATE', 'Haryana', 0, TRUE) // Test For UAT
                    else
                        WriteToGlbTextVar('SHIP_STATE', 'Delhi', 0, TRUE)// Test For UAT

                END;

            WriteToGlbTextVar('SHIP_CITY_NAME', SalesInvoiceHeader."Ship-to City", 0, TRUE);
            // 15800 Open For Production WriteToGlbTextVar('SHIP_PIN_CODE', SalesInvoiceHeader."Ship-to Post Code", 0, TRUE);
            if SalesInvLine."GST Jurisdiction Type" = SalesInvLine."GST Jurisdiction Type"::Intrastate then
                WriteToGlbTextVar('SHIP_PIN_CODE', '123401', 0, TRUE) // Test For UAT
            else
                WriteToGlbTextVar('SHIP_PIN_CODE', '110001', 0, TRUE); // Test For UAT

            Country.GET(SalesInvoiceHeader."Ship-to Country/Region Code");
            WriteToGlbTextVar('SHIP_COUNTRY', FORMAT(Country.Name), 0, TRUE);

            if SalesInvoiceHeader.Alternative <> '' then begin
                AlternativeAdrees.Reset();
                AlternativeAdrees.SetRange("Employee No.", 'PIPL');
                AlternativeAdrees.SetRange(Code, SalesInvoiceHeader.Alternative);
                if AlternativeAdrees.FindFirst() then begin
                    Location.GET(SalesInvoiceHeader."Location Code");
                    LocAdd := Location.Address + ' ,' + Location."Address 2";
                    WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', AlternativeAdrees.Address + ' ,' + AlternativeAdrees."Address 2", 0, TRUE);
                    State.GET(AlternativeAdrees.EIN_State);
                    WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);
                    WriteToGlbTextVar('ORIGIN_CITY_NAME', AlternativeAdrees.City, 0, TRUE);
                    WriteToGlbTextVar('ORIGIN_PIN_CODE', AlternativeAdrees."Post Code", 0, TRUE);
                end;
            end else begin
                Location.GET(SalesInvoiceHeader."Location Code");
                LocAdd := Location.Address + ' ,' + Location."Address 2";
                WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', LocAdd, 0, TRUE);
                State.GET(Location."State Code");
                WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);
                WriteToGlbTextVar('ORIGIN_CITY_NAME', Location.City, 0, TRUE);
                WriteToGlbTextVar('ORIGIN_PIN_CODE', Location."Post Code", 0, TRUE);

            end;

            IF GSTRegistrationNos.GET(Location."GST Registration No.") THEN;
            WriteToGlbTextVar('TRANSPORT_MODE', 'null', 1, TRUE);
            WriteToGlbTextVar('VEHICLE_TYPE', 'null', 1, TRUE);
            IF Transporter.GET(SalesInvoiceHeader."Transporter Code") THEN
                // 15800 Open For Production   WriteToGlbTextVar('TRANSPORTER_ID_GSTIN', Transporter."GST Registration No.", 0, TRUE);
                WriteToGlbTextVar('TRANSPORTER_ID_GSTIN', '05AAACE1378A1Z9', 0, TRUE); // Test For UAT.
            WriteToGlbTextVar('APPROXIMATE_DISTANCE', FORMAT(SalesInvoiceHeader."Distance (Km)"), 1, TRUE);
            WriteToGlbTextVar('TRANS_DOC_NO', SalesInvoiceHeader."LR/RR No.", 0, TRUE);
            WriteToGlbTextVar('TRANS_DOC_DATE', FORMAT(SalesInvoiceHeader."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
            WriteToGlbTextVar('VEHICLE_NO', SalesInvoiceHeader."Vehicle No.", 0, TRUE);

            DtldGSTLedgEntry2.RESET;
            DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgerEntry."Document No.");
            DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Entry Type", DtldGSTLedgEntry2."Entry Type"::"Initial Entry");
            IF DtldGSTLedgEntry2.FINDSET THEN
                REPEAT
                    IF PreviousLineNo <> DtldGSTLedgEntry2."Document Line No." THEN
                        AssVal += ABS(GetAssValue(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No."));
                    PreviousLineNo := DtldGSTLedgEntry2."Document Line No.";
                UNTIL DtldGSTLedgEntry2.NEXT = 0;

            DtldGSTLedgEntry2.RESET;
            DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document Type", DtldGSTLedgerEntry."Document Type");
            DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgerEntry."Document No.");
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
            DtldGSTLedgEntry2.SETRANGE("Document No.", DtldGSTLedgerEntry."Document No.");
            IF DtldGSTLedgerEntry."Item Charge Entry" THEN BEGIN
                if DetailedGSTLedgerInfo.Get(DtldGSTLedgerEntry."Entry No.") then;
                DtldGSTLedgEntry2.SETRANGE("Original Invoice No.", DtldGSTLedgerEntry."Original Invoice No.");
                // DtldGSTLedgEntry2.SETRANGE("Item Charge Assgn. Line No.", DetailedGSTLedgerInfo."Item Charge Assgn. Line No."); // 15800
            END;
            IF DtldGSTLedgEntry2.FINDSET THEN
                REPEAT
                    IF DtldGSTLedgEntry2."GST Component Code" = 'CESS' then
                        CessNonAdVal += ABS(DtldGSTLedgEntry2."GST Amount");
                UNTIL DtldGSTLedgEntry2.NEXT = 0;
            StCessVal := CessNonAdVal;



            WriteToGlbTextVar('CGST_AMOUNT', FORMAT(ABS(CGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('SGST_AMOUNT', FORMAT(ABS(SGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('IGST_AMOUNT', FORMAT(ABS(IGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('CESS_AMOUNT', FORMAT(ABS(CessVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('TOTAL_TAXABLE_VALUE', FORMAT(ABS(AssVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('OTHER_VALUE', FORMAT(ABS(GetTCSAmount(DtldGSTLedgerEntry."Document No.")) +
                                    GetFreight(DtldGSTLedgerEntry."Document No.") +
                                      GetStrucDisc(DtldGSTLedgerEntry."Document No."), 0, 2), 1, TRUE);
            WriteToGlbTextVar('TOTAL_INVOICE_VALUE', FORMAT(GetTotalInvValue(DtldGSTLedgerEntry."Document No."), 0, 2), 1, TRUE);
            TotalInvVal := AssVal + CGSTVal + SGSTVal + IGSTVal + CessVal + CessNonAdVal + StCessVal;
            TotalInvoiceAmt := AssVal + CGSTVal + SGSTVal + IGSTVal + CessVal + (ABS(GetTCSAmount(DtldGSTLedgerEntry."Document No.")) +
                                    GetFreight(DtldGSTLedgerEntry."Document No.") +
                                      GetStrucDisc(DtldGSTLedgerEntry."Document No."));
            TotaInvoiceValueCheck := GetTotalInvValue(DtldGSTLedgerEntry."Document No.");
            GlbTextVar += '"Items" : [';
            WriteItemListEWB(DtldGSTLedgerEntry);
            GlbTextVar += ']';
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';

            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("User Name");
            ROBOSetup.TestField(Password);
            /*ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
            ROBOSetup.TESTFIELD("URL E-Way");
             */
            Message('%1', GlbTextVar);
            if TotaInvoiceValueCheck < TotalInvoiceAmt then
                Error('Total invoice value cannot be less than the sum of total assessible value and tax values');
            EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
            EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
            EinvoiceHttpRequest.Method := 'POST';
            if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                JResultObject.ReadFrom(ResultMessage);
                Message(ResultMessage);
                Char13 := 13;
                Char10 := 10;
                NewLine := FORMAT(Char10) + FORMAT(Char13);
                ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
          + ResultMessage + NewLine + '-----------------------------------------------------------';

                if JResultObject.Get('MessageId', JResultToken) then
                    if JResultToken.AsValue().AsInteger() = 1 then begin
                        if JResultObject.Get('Message', JResultToken) then;
                        Message(Format(JResultToken));
                    end else
                        if JResultObject.Get('Message', JResultToken) then
                            Message(Format(JResultToken));

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsArray then begin
                        JResultToken.WriteTo(OutputMessage);
                        JResultArray.ReadFrom(OutputMessage);
                        if JResultArray.Get(0, JOutputToken) then begin
                            if JOutputToken.IsObject then begin
                                JOutputToken.WriteTo(OutputMessage);
                                JOutputObject.ReadFrom(OutputMessage);
                            end;
                        end;

                        if JOutputObject.Get('REMARKS', JOutputToken) then
                            Remarks := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('STATUS', JOutputToken) then
                            Status := JOutputToken.AsValue().AsText();
                        Message(ReturnMsg, Remarks, Status);

                        ROBOOutput.SETRANGE("Document No.", DocNo);
                        IF ROBOOutput.FINDSET THEN BEGIN
                            ROBOOutput."Generate Invoice Details".CreateOutStream(StoreOutStrm);
                            StoreOutStrm.WriteText(GlbTextVar);
                            Clear(StoreOutStrm);
                            ROBOOutput."Output Payload Invoice Details".CreateOutStream(StoreOutStrm);
                            StoreOutStrm.WriteText(ErrorLogMessage);
                            ROBOOutput.MODIFY;

                        END;
                    end;
            end else
                Message('Generation Invoice Detail Failed!!');

            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                EWayAPI.InvoiceDetails(ROBOSetup."URL E-Way",
                                      ROBOSetup."Eway Private Key",
                                      ROBOSetup."Eway Private Value",
                                      ROBOSetup.IPAddress,
                                      GlbTextVar,
                                      ROBOSetup."Error File Save Path",
                                      EwayMessageID,
                                      EwayMessage,
                                      DataText,
                                      Remarks,
                                      Status);
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            //           TaxProOutput.INIT;
            //           TaxProOutput."Document Type" := DocType;
            //           TaxProOutput."Document No." := DocNo;
            //           IF NOT TaxProOutput.INSERT THEN
            //             TaxProOutput.MODIFY;
        END;
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

    local procedure WriteItemListEWB(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry")
    var
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        DtldGSTLedgEntry3: Record "Detailed GST Ledger Entry";
        TaxProEInvoicingBuffer: Record 50013 temporary;
        Item: Record 27;
        UnitofMeasure: Record 204;
        "CGST%": Text;
        "SGST%": Text;
        "IGST%": Text;
        "CESS%": Text;
        TotalLines: Integer;
        LineCnt: Integer;
        "GST%": Decimal;
        ItemName: Text[100];
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                if DGLInfo.get(DtldGSTLedgEntry2."Entry No.") then;
                IF NOT TaxProEInvoicingBuffer.GET(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry2."Document Line No.", DtldGSTLedgEntry2."Original Invoice No.", DGLInfo."Item Charge Assgn. Line No.") THEN BEGIN
                    TaxProEInvoicingBuffer.INIT;
                    TaxProEInvoicingBuffer."Document No." := DtldGSTLedgEntry2."Document No.";
                    TaxProEInvoicingBuffer."Document Line No." := DtldGSTLedgEntry2."Document Line No.";
                    TaxProEInvoicingBuffer."Original Invoice No." := DtldGSTLedgEntry2."Original Invoice No.";
                    TaxProEInvoicingBuffer."Item Charge Line No." := DGLInfo."Item Charge Assgn. Line No.";
                    TaxProEInvoicingBuffer.INSERT;
                END;
            UNTIL DtldGSTLedgEntry2.NEXT = 0;

        TaxProEInvoicingBuffer.RESET;
        TotalLines := TaxProEInvoicingBuffer.COUNT;
        "SGST%" := 'null';
        "IGST%" := 'null';
        "CESS%" := 'null';
        "CGST%" := 'null';

        TaxProEInvoicingBuffer.RESET;
        IF TaxProEInvoicingBuffer.FINDSET THEN
            REPEAT
                LineCnt += 1;
                DtldGSTLedgEntry2.RESET;
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", TaxProEInvoicingBuffer."Document No.");
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document Line No.", TaxProEInvoicingBuffer."Document Line No.");
                DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Original Invoice No.", TaxProEInvoicingBuffer."Original Invoice No.");
                DGLInfo.SETRANGE(DGLInfo."Item Charge Assgn. Line No.", TaxProEInvoicingBuffer."Item Charge Line No."); // 15800
                IF DtldGSTLedgEntry2.FINDFIRST THEN BEGIN
                    "GST%" := 0;
                    GlbTextVar += '{';

                    DtldGSTLedgEntry3.RESET;
                    DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document No.", DtldGSTLedgEntry2."Document No.");
                    DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document Line No.", DtldGSTLedgEntry2."Document Line No.");
                    IF DtldGSTLedgEntry3.FINDSET THEN
                        REPEAT

                            IF DtldGSTLedgEntry3."GST Component Code" = 'CGST' THEN
                                "CGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
                            ELSE
                                IF DtldGSTLedgEntry3."GST Component Code" = 'SGST' THEN
                                    "SGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
                                ELSE
                                    IF DtldGSTLedgEntry3."GST Component Code" = 'IGST' THEN
                                        "IGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
                                    ELSE
                                        IF DtldGSTLedgEntry3."GST Component Code" = 'CESS' THEN
                                            "CESS%" := FORMAT(DtldGSTLedgEntry3."GST %");
                            "GST%" += DtldGSTLedgEntry3."GST %";
                        UNTIL DtldGSTLedgEntry3.NEXT = 0;

                    WriteToGlbTextVar('IGST_RATE', "IGST%", 1, TRUE);
                    WriteToGlbTextVar('SGST_RATE', "SGST%", 1, TRUE);
                    WriteToGlbTextVar('CGST_RATE', "CGST%", 1, TRUE);
                    WriteToGlbTextVar('CESS_RATE', "CESS%", 2, TRUE);
                    WriteToGlbTextVar('CESS_NONADVOL', FORMAT(ABS(0), 0, 2), 1, TRUE);

                    Item.GET(DtldGSTLedgEntry2."No.");
                    if DGLInfo.Get(DtldGSTLedgEntry2."Entry No.") then;
                    UnitofMeasure.GET(DGLInfo.UOM);
                    ItemName := Item."No." + '-' + Item."Full Description";
                    //WriteToGlbTextVar('ITEM_NAME',Item."No.",0,TRUE);
                    WriteToGlbTextVar('ITEM_NAME', ItemName, 0, TRUE);

                    WriteToGlbTextVar('HSN_CODE', DtldGSTLedgEntry2."HSN/SAC Code", 0, TRUE);

                    WriteToGlbTextVar('UOM', UnitofMeasure."UOM For E Invoicing", 0, TRUE); // 15800 UnitofMeasure."GST Reporting UQC"

                    WriteToGlbTextVar('QUANTITY', FORMAT(ABS(DtldGSTLedgEntry2.Quantity), 0, 2), 1, TRUE);

                    WriteToGlbTextVar('TAXABLE_VALUE', FORMAT(ABS((DtldGSTLedgEntry2."GST Base Amount")), 0, 2), 1, FALSE);

                    IF LineCnt <> TotalLines THEN
                        GlbTextVar += '},'
                    ELSE
                        GlbTextVar += '}'
                END;
            UNTIL TaxProEInvoicingBuffer.NEXT = 0;
    end;

    procedure UpdateDistance(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        DistanceMessage: Text;
    begin
        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'DISTANCE', 0, FALSE);
            GlbTextVar += '}';

            /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
             */ // 15800
                //MESSAGE(GlbTextVar);

            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                EWayAPI.UpdateDistance(ROBOSetup."URL E-Inv",
                                                   ROBOSetup."Eway Private Key",
                                                   ROBOSetup."Eway Private Value",
                                                   ROBOSetup.IPAddress,
                                                   GlbTextVar,
                                                   ROBOSetup."Error File Save Path",
                                                   DistanceMessID,
                                                   DistanceMessage,
                                                   DataText,
                                                   Remarks,
                                                   Status,
                                                   ApproxDistance);
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            MESSAGE(DistanceMessage);
        END;
    end;

    procedure CalculateDistance(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        Remarks: Text;
        Status: Text;
        Location: Record 14;
        OriginPinCode: Text;
        ShipPinCode: Text;
        SalesInvoiceHeader: Record 112;
        ApproxDistance: Text;
        ReturnMsg: Label 'Status : %1\ %2';
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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JResultArray: JsonArray;
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        SalesInvoiceHeader.GET(DocNo);
        SalesInvoiceHeader.TESTFIELD("Distance (Km)", 0);
        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'DISTANCE', 0, FALSE);
            GlbTextVar += '}';

            Location.GET(DtldGSTLedgerEntry."Location Code");
            Location.TESTFIELD("Post Code");

            OriginPinCode := Location."Post Code";
            ShipPinCode := SalesInvoiceHeader."Ship-to Post Code";

            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("User Name");
            ROBOSetup.TestField(Password);
            /*  ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
             ROBOSetup.TESTFIELD("Eway Private Key");
             ROBOSetup.TESTFIELD("Eway Private Value");
             ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
             ROBOSetup.TESTFIELD(ROBOSetup.user_name);
             ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
             ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
            MESSAGE(GlbTextVar);

            EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
            EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
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
                    if JResultToken.AsValue().AsInteger() = 1 then begin
                        if JResultObject.Get('Message', JResultToken) then;
                        Message(Format(JResultToken));
                    end else
                        if JResultObject.Get('Message', JResultToken) then
                            Message(Format(JResultToken));

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsArray then begin
                        JResultToken.WriteTo(OutputMessage);
                        JResultArray.ReadFrom(OutputMessage);
                        if JResultArray.Get(0, JOutputToken) then begin
                            if JOutputToken.IsObject then begin
                                JOutputToken.WriteTo(OutputMessage);
                                JOutputObject.ReadFrom(OutputMessage);
                            end;
                        end;

                        if JOutputObject.Get('REMARKS', JOutputToken) then
                            Remarks := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('STATUS', JOutputToken) then
                            Status := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('APPROXIMATE_DISTANCE', JOutputToken) then
                            ApproxDistance := JOutputToken.AsValue().AsText();
                        MESSAGE(ReturnMsg, Status, Remarks);
                    end;
            end else
                Message('Error When Contacting API');

            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                EWayAPI.CalculateDistance(ROBOSetup."URL E-Way",
                                                   ROBOSetup."Eway Private Key",
                                                   ROBOSetup."Eway Private Value",
                                                   ROBOSetup.IPAddress,
                                                   GlbTextVar,
                                                   ROBOSetup."Error File Save Path",
                                                   DistanceMessID,
                                                   DistanceMessage,
                                                   DataText,
                                                   Remarks,
                                                   Status,
                                                   OriginPinCode,
                                                   ShipPinCode,
                                                   ApproxDistance);
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
        END;
    end;

    procedure GeneratePARTA(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SalesInvoiceHeader: Record 112;
        EWBNo: Text;
        Remarks: Text;
        Status: Text;
        ROBOOutput: Record 50014;
        ReturnMsg: Label 'Status : %1\ %2';
        EwayGenErr: Label 'Eway Billl is already generated with No. %1';

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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JResultArray: JsonArray;

    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        SalesInvoiceHeader.GET(DocNo);
        SalesInvoiceHeader.SETAUTOCALCFIELDS("EWay Generated", "Eway Cancelled");
        SalesInvoiceHeader.TESTFIELD("EWay Generated", FALSE);
        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDSET THEN BEGIN
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'SYNCEWAYBILL', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            WriteToGlbTextVar('GENERATOR_GSTIN', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
                                                                              // 15800 Open For Production WriteToGlbTextVar('GENERATOR_GSTIN', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
            WriteToGlbTextVar('DOC_NO', DtldGSTLedgerEntry."Document No.", 0, TRUE);

            IF SalesInvoiceHeader."Invoice Type" IN [SalesInvoiceHeader."Invoice Type"::"Bill of Supply"] THEN
                WriteToGlbTextVar('DOC_TYPE', 'Bill of Supply', 0, FALSE)
            ELSE
                WriteToGlbTextVar('DOC_TYPE', 'Tax Invoice', 0, FALSE);
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';
            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("User Name");
            ROBOSetup.TestField(Password);
            /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password); */
            MESSAGE(GlbTextVar);

            EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
            EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
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
                    if JResultToken.AsValue().AsInteger() = 1 then begin
                        if JResultObject.Get('Message', JResultToken) then;
                        Message(Format(JResultToken));
                    end else
                        if JResultObject.Get('Message', JResultToken) then
                            Message(Format(JResultToken));

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsArray then begin
                        JResultToken.WriteTo(OutputMessage);
                        JResultArray.ReadFrom(OutputMessage);
                        if JResultArray.Get(0, JOutputToken) then begin
                            if JOutputToken.IsObject then begin
                                JOutputToken.WriteTo(OutputMessage);
                                JOutputObject.ReadFrom(OutputMessage);
                            end;
                        end;

                        if JOutputObject.Get('REMARKS', JOutputToken) then
                            Remarks := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('STATUS', JOutputToken) then
                            Status := JOutputToken.AsValue().AsText();
                        if JOutputObject.Get('EWB_NO', JOutputToken) then
                            EWBNo := JOutputToken.AsValue().AsText();
                    end;
            end else
                Message('Error When Contacting API');

            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                EWayAPI.GeneratePartA(ROBOSetup."URL E-Way",
                                                ROBOSetup."Eway Private Key",
                                                ROBOSetup."Eway Private Value",
                                                ROBOSetup.IPAddress,
                                                GlbTextVar,
                                                ROBOSetup."Error File Save Path",
                                                PartAMessId,
                                                PartAMessage,
                                                DataText,
                                                Remarks,
                                                Status,
                                                EWBNo);
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/

            IF EWBNo <> '' THEN BEGIN
                ROBOOutput.SETRANGE("Document No.", DocNo);
                IF ROBOOutput.FINDSET THEN BEGIN
                    IF ROBOOutput."Eway Bill No" <> '' THEN
                        ERROR(EwayGenErr, ROBOOutput."Eway Bill No");
                    ROBOOutput."Eway Bill No" := EWBNo;
                    ROBOOutput."Eway Generated" := TRUE;
                    ROBOOutput."Output Payload E-Way Bill".CreateOutStream(StoreOutStrm);
                    StoreOutStrm.WriteText(ErrorLogMessage);
                    ROBOOutput.MODIFY;
                END;
            END;
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure UPDATEPARTB(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JResultArray: JsonArray;

        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SalesInvoiceHeader: Record 112;
        Location: Record 14;
        ROBOOutput: Record 50014;
        State: Record State;
        TransportMethod: Record 259;
        Remarks: Text;
        Status: Text;
        ReturnMsg: Label 'Status : %1\ %2';
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        SalesInvoiceHeader.GET(DocNo);
        SalesInvoiceHeader.TESTFIELD("Vehicle Type");
        SalesInvoiceHeader.TESTFIELD("Vehicle No.");

        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDFIRST THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);
            DtldGSTLedgerEntry.RESET;
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
            IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
                GlbTextVar := '';
                GlbTextVar += '{';
                WriteToGlbTextVar('action', 'UPDATEPARTB', 0, TRUE);
                GlbTextVar += '"data": [';
                GlbTextVar += '{';
                WriteToGlbTextVar('GENERATOR_GSTIN', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
                                                                                  // 15800 Open For Production   WriteToGlbTextVar('Generator_Gstin', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
                WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);

                TransportMethod.GET(SalesInvoiceHeader."Transport Method");
                WriteToGlbTextVar('TransportMode', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
                WriteToGlbTextVar('VEHICLE_TYPE', FORMAT(SalesInvoiceHeader."Vehicle Type"), 0, TRUE);
                WriteToGlbTextVar('VehicleNo', SalesInvoiceHeader."Vehicle No.", 0, TRUE);
                IF TransportMethod."Transportation Mode" IN [TransportMethod."Transportation Mode"::Air,
                                                    TransportMethod."Transportation Mode"::Rail,
                                                    TransportMethod."Transportation Mode"::Ship] THEN BEGIN
                    WriteToGlbTextVar('TransDocNumber', SalesInvoiceHeader."No.", 0, TRUE);
                    WriteToGlbTextVar('TransDocDate', FORMAT(SalesInvoiceHeader."Document Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
                END;

                Location.GET(DtldGSTLedgerEntry."Location Code");
                State.GET(Location."State Code");

                WriteToGlbTextVar('StateName', State.Description, 0, TRUE);
                WriteToGlbTextVar('FromCityPlace', Location.City, 0, TRUE);
                WriteToGlbTextVar('VehicleReason', SalesInvoiceHeader."Vehicle Change Reason", 0, TRUE);
                WriteToGlbTextVar('Remarks', '', 0, FALSE);
                GlbTextVar += '}';
                GlbTextVar += ']';
                GlbTextVar += '}';

                MESSAGE(GlbTextVar);
                /*  ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                 ROBOSetup.TESTFIELD("Eway Private Key");
                 ROBOSetup.TESTFIELD("Eway Private Value");
                 ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                 ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                 ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                 ROBOSetup.TESTFIELD(ROBOSetup.Password);
  */// 15800

                EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
                EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
                EinvoiceHttpHeader.Clear();
                EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
                EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
                EinvoiceHttpHeader.Add('Content-Type', 'application/json');
                EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
                EinvoiceHttpRequest.Content := EinvoiceHttpContent;
                EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
                EinvoiceHttpRequest.Method := 'POST';
                if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                    EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                    JResultObject.ReadFrom(ResultMessage);
                    Char13 := 13;
                    Char10 := 10;
                    NewLine := FORMAT(Char10) + FORMAT(Char13);
                    ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
              + ResultMessage + NewLine + '-----------------------------------------------------------';

                    if JResultObject.Get('MessageId', JResultToken) then
                        if JResultToken.AsValue().AsInteger() = 1 then begin
                            if JResultObject.Get('Message', JResultToken) then;
                            Message(Format(JResultToken));
                        end else
                            if JResultObject.Get('Message', JResultToken) then
                                Message(Format(JResultToken));

                    if JResultObject.Get('Data', JResultToken) then
                        if JResultToken.IsArray then begin
                            JResultToken.WriteTo(OutputMessage);
                            JResultArray.ReadFrom(OutputMessage);
                            if JResultArray.Get(0, JOutputToken) then begin
                                if JOutputToken.IsObject then begin
                                    JOutputToken.WriteTo(OutputMessage);
                                    JOutputObject.ReadFrom(OutputMessage);
                                end;
                            end;

                            if JOutputObject.Get('Remarks', JOutputToken) then
                                Remarks := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('Status', JOutputToken) then
                                Status := JOutputToken.AsValue().AsText();
                            Message(ReturnMsg, Remarks, Status);
                        end;
                end else
                    Message('Generation Invoice Detail Failed!!');

                /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                      EWayAPI.UpdatePartB(ROBOSetup."URL E-Way",
                                                    ROBOSetup."Eway Private Key",
                                                    ROBOSetup."Eway Private Value",
                                                    ROBOSetup.IPAddress,
                                                    GlbTextVar,
                                                    ROBOSetup."Error File Save Path",
                                                    PartBMessId,
                                                    PartBMessage,
                                                    DataText,
                                                    Remarks,
                                                    Status,
                                                    ROBOOutput."Eway Bill No",
                                                    VehicleDate,
                                                    EWBValidUpto);
                //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            END;
        END;
    end;

    procedure CancelEwayBill(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JResultArray: JsonArray;

        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        ROBOOutput: Record 50014;
        Remarks: Text;
        Status: Text;
        EWBCancelDate: Text;
        NoEwayBillErr: Label 'No Eway Bill found against invoice no.%1';
        ReturnMsg: Label 'Status : %1\ %2';
        SalesInvoiceHeader: Record 112;
        ReasonCode: Record 231;
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        ROBOOutput.SETRANGE("Eway Generated", TRUE);
        ROBOOutput.SETRANGE("Eway Cancel", FALSE);
        IF NOT ROBOOutput.FINDSET THEN
            ERROR(NoEwayBillErr, DocNo);

        SalesInvoiceHeader.GET(DocNo);
        SalesInvoiceHeader.TESTFIELD("Eway Cancel Reason");
        ReasonCode.GET(SalesInvoiceHeader."Eway Cancel Reason");
        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDSET THEN BEGIN
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'CANCEL', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            // 15800 Open For Production WriteToGlbTextVar('Generator_Gstin', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
            WriteToGlbTextVar('GENERATOR_GSTIN', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
            WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
            WriteToGlbTextVar('CancelReason', ReasonCode.Description, 0, TRUE);
            WriteToGlbTextVar('cancelRmrk', SalesInvoiceHeader."Eway Cancel Remark", 0, FALSE);
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';
            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("User Name");
            ROBOSetup.TestField(Password);
            /*  ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
             ROBOSetup.TESTFIELD("Eway Private Key");
             ROBOSetup.TESTFIELD("Eway Private Value");
             ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
             ROBOSetup.TESTFIELD(ROBOSetup.user_name);
             ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
             ROBOSetup.TESTFIELD(ROBOSetup.Password);
  */
            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                  EWayAPI.CancelEWayBill(ROBOSetup."URL E-Way",
                                                  ROBOSetup."Eway Private Key",
                                                  ROBOSetup."Eway Private Value",
                                                  ROBOSetup.IPAddress,
                                                  GlbTextVar,
                                                  ROBOSetup."Error File Save Path",
                                                  CancelMessId,
                                                  CancelMessage,
                                                  DataText,
                                                  Remarks,
                                                  Status,
                                                  ROBOOutput."Eway Bill No",
                                                  EWBCancelDate);
            //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
            EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
            EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
            EinvoiceHttpHeader.Clear();
            EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
            EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
            EinvoiceHttpHeader.Add('Content-Type', 'application/json');
            EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
            EinvoiceHttpRequest.Content := EinvoiceHttpContent;
            EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
            EinvoiceHttpRequest.Method := 'POST';
            if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                JResultObject.ReadFrom(ResultMessage);
                /* Message(ResultMessage);
                Char13 := 13;
                Char10 := 10;
                NewLine := FORMAT(Char10) + FORMAT(Char13);
                ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
          + ResultMessage + NewLine + '-----------------------------------------------------------';
 */
                if JResultObject.Get('MessageId', JResultToken) then
                    if JResultToken.AsValue().AsInteger() = 1 then begin
                        if JResultObject.Get('Message', JResultToken) then;
                        Message(Format(JResultToken));
                    end else
                        if JResultObject.Get('Message', JResultToken) then
                            Message(Format(JResultToken));

                if JResultObject.Get('Data', JResultToken) then
                    if JResultToken.IsArray then begin
                        JResultToken.WriteTo(OutputMessage);
                        JResultArray.ReadFrom(OutputMessage);
                        if JResultArray.Get(0, JOutputToken) then begin
                            if JOutputToken.IsObject then begin
                                JOutputToken.WriteTo(OutputMessage);
                                JOutputObject.ReadFrom(OutputMessage);
                            end;
                        end;

                        if JOutputObject.Get('CancelDate', JOutputToken) then
                            EWBCancelDate := JOutputToken.AsValue().AsText();
                        Evaluate(YearCode, CopyStr(EWBCancelDate, 1, 4));
                        Evaluate(MonthCode, CopyStr(EWBCancelDate, 6, 2));
                        Evaluate(DayCode, CopyStr(EWBCancelDate, 9, 2));
                        Evaluate(EWayBillDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(EWBCancelDate, 12, 8));
                    end;
            end else
                Message('Generation Invoice Detail Failed!!');
            ROBOOutput."Eway Bill Cancel Date" := Format(EWayBillDate);
            ROBOOutput."Eway Cancel" := TRUE;
            ROBOOutput.MODIFY;
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure UpdateTransporter(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund; TransportCode: Code[20])
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        ROBOOutput: Record 50014;
        Remarks: Text;
        Status: Text;
        ReturnMsg: Label 'Status : %1\ %2';
        Transporter: Record 23;
        DetailedGSTLedgerInfo: Record "Detailed GST Ledger Entry Info";
        LocAdd: Text[100];
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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        GSTRegistrationNos: Record "GST Registration Nos.";
        JResultArray: JsonArray;
        TotalInvoiceAmt: Decimal;
        TotaInvoiceValueCheck: Decimal;
    begin
        EInvoiceSetUp.Get();
        Transporter.GET(TransportCode);
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDSET THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);
            DtldGSTLedgerEntry.RESET;
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
            IF DtldGSTLedgerEntry.FINDSET THEN BEGIN
                GlbTextVar := '';
                GlbTextVar += '{';
                WriteToGlbTextVar('action', 'UPDATETRANSPORTER', 0, TRUE);
                GlbTextVar += '"data": [';
                GlbTextVar += '{';
                // 15800 Open For Production WriteToGlbTextVar('Generator_Gstin', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
                WriteToGlbTextVar('GENERATOR_GSTIN', '05AAACE1268K1ZR', 0, TRUE); // Test For UAT
                WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
                // 15800 Open For Production  WriteToGlbTextVar('Transport_Gstin', Transporter."GST Registration No.", 0, FALSE);
                WriteToGlbTextVar('Transport_Gstin', '05AAACE1378A1Z9', 0, FALSE);// Test For UAT
                GlbTextVar += '{';
                GlbTextVar += ']';
                GlbTextVar += '}';

                Message('%1', GlbTextVar);
                EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
                EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
                EinvoiceHttpHeader.Clear();
                EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
                EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
                EinvoiceHttpHeader.Add('Content-Type', 'application/json');
                EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
                EinvoiceHttpRequest.Content := EinvoiceHttpContent;
                EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
                EinvoiceHttpRequest.Method := 'POST';
                if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                    EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                    JResultObject.ReadFrom(ResultMessage);
                    Char13 := 13;
                    Char10 := 10;
                    NewLine := FORMAT(Char10) + FORMAT(Char13);
                    ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
              + ResultMessage + NewLine + '-----------------------------------------------------------';

                    if JResultObject.Get('MessageId', JResultToken) then
                        if JResultToken.AsValue().AsInteger() = 1 then begin
                            if JResultObject.Get('Message', JResultToken) then;
                            Message(Format(JResultToken));
                        end else
                            if JResultObject.Get('Message', JResultToken) then
                                Message(Format(JResultToken));

                    if JResultObject.Get('Data', JResultToken) then
                        if JResultToken.IsArray then begin
                            JResultToken.WriteTo(OutputMessage);
                            JResultArray.ReadFrom(OutputMessage);
                            if JResultArray.Get(0, JOutputToken) then begin
                                if JOutputToken.IsObject then begin
                                    JOutputToken.WriteTo(OutputMessage);
                                    JOutputObject.ReadFrom(OutputMessage);
                                end;
                            end;

                            if JOutputObject.Get('Remarks', JOutputToken) then
                                Remarks := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('Status', JOutputToken) then
                                Status := JOutputToken.AsValue().AsText();
                            Message(ReturnMsg, Remarks, Status);
                        end;
                end else
                    Message('Generation Invoice Detail Failed!!');

                /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                 ROBOSetup.TESTFIELD(ROBOSetup.client_id);
                 ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
                 ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                 ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                 ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                 ROBOSetup.TESTFIELD(ROBOSetup.Password);

                 //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                       EWayAPI.CancelEWayBill(ROBOSetup."URL E-Way",
                                                       ROBOSetup."Eway Private Key",
                                                       ROBOSetup."Eway Private Value",
                                                       ROBOSetup.IPAddress,
                                                       GlbTextVar,
                                                       ROBOSetup."Error File Save Path",
                                                       UpdTptMessId,
                                                       UpdateTptMessage,
                                                       DataText,
                                                       Remarks,
                                                       Status,
                                                       ROBOOutput."Eway Bill No",
                                                       EWBCancelDate);
                                                       //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/

            END;
        END;
    end;

    procedure ExtendValidity(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        ROBOOutput: Record 50014;
        Remarks: Text;
        Status: Text;
        SalesInvoiceHeader: Record 112;
        Location: Record 14;
        State: Record State;
        ExtensionReason: Text;
        TransportMethod: Record 259;
        ValidUpto: Text;
        ReturnMsg: Label 'Status : %1\ %2';
        ExtenResonErr: Label 'Please specify extension reason.';
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
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        GSTRegistrationNos: Record "GST Registration Nos.";
        JResultArray: JsonArray;
        TotalInvoiceAmt: Decimal;
        TotaInvoiceValueCheck: Decimal;

    begin
        EInvoiceSetUp.Get();
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDSET THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);
            DtldGSTLedgerEntry.RESET;
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
            IF DtldGSTLedgerEntry.FINDSET THEN BEGIN
                SalesInvoiceHeader.GET(DtldGSTLedgerEntry."Document No.");
                Location.GET(SalesInvoiceHeader."Location Code");
                State.GET(Location."State Code");

                CASE SalesInvoiceHeader."Eway Extension Reason" OF
                    SalesInvoiceHeader."Eway Extension Reason"::"Natural Calamity":
                        ExtensionReason := 'Natural Calamity';
                    SalesInvoiceHeader."Eway Extension Reason"::"Law and Order Situation":
                        ExtensionReason := 'Law and Order Situation';
                    SalesInvoiceHeader."Eway Extension Reason"::Transshipment:
                        ExtensionReason := 'Transshipment';
                    SalesInvoiceHeader."Eway Extension Reason"::Accident:
                        ExtensionReason := 'Accident';
                    SalesInvoiceHeader."Eway Extension Reason"::Others:
                        ExtensionReason := 'Others';
                    SalesInvoiceHeader."Eway Extension Reason"::" ":
                        ERROR(ExtenResonErr);
                END;

                TransportMethod.GET(SalesInvoiceHeader."Transport Method");

                GlbTextVar := '';
                GlbTextVar += '{';
                WriteToGlbTextVar('action', 'EXTENDVALIDITY', 0, TRUE);
                GlbTextVar += '"data": [';
                GlbTextVar += '{';
                WriteToGlbTextVar('Generator_Gstin', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
                WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
                WriteToGlbTextVar('VehicleNo', SalesInvoiceHeader."Vehicle No.", 0, TRUE);
                WriteToGlbTextVar('FromCity', Location.City, 0, TRUE);
                WriteToGlbTextVar('FromState', State.Description, 0, TRUE);
                WriteToGlbTextVar('ExtnRsn', ExtensionReason, 0, TRUE);
                WriteToGlbTextVar('ExtnRemarks', '', 0, TRUE);
                WriteToGlbTextVar('TransDocNumber', FORMAT(SalesInvoiceHeader."LR/RR No."), 0, TRUE);
                WriteToGlbTextVar('TransDocDate', FORMAT(SalesInvoiceHeader."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
                WriteToGlbTextVar('TransportMode', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
                WriteToGlbTextVar('RemainingDistance', FORMAT(SalesInvoiceHeader."Eway Remaining (Km)"), 0, TRUE);
                WriteToGlbTextVar('TransitType', FORMAT(SalesInvoiceHeader."Eway Extension Transit Type"), 0, TRUE);
                WriteToGlbTextVar('FromPincode', Location."Post Code", 0, TRUE);
                WriteToGlbTextVar('AddressLine1', Location.Address, 0, TRUE);
                WriteToGlbTextVar('AddressLine2', Location."Address 2", 0, TRUE);
                WriteToGlbTextVar('AddressLine3', '', 0, FALSE);
                GlbTextVar += '}';
                GlbTextVar += ']';
                GlbTextVar += '}';

                /*ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                ROBOSetup.TESTFIELD(ROBOSetup.client_id);
                ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
                ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                ROBOSetup.TESTFIELD(ROBOSetup.Password);

                //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                     EWayAPI.ExtendValidity(ROBOSetup."URL E-Way",
                                                      ROBOSetup."Eway Private Key",
                                                      ROBOSetup."Eway Private Value",
                                                      ROBOSetup.IPAddress,
                                                      GlbTextVar,
                                                      ROBOSetup."Error File Save Path",
                                                      ExtMessageId,
                                                      ExtMessage,
                                                      DataText,
                                                      Remarks,
                                                      Status,
                                                      UpdatedDate,
                                                      ValidUpto);
                //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/
                Message(GlbTextVar);
                EinvoiceHttpContent.WriteFrom(Format(GlbTextVar));
                EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
                EinvoiceHttpHeader.Clear();
                EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetUp."Private Key");
                EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetUp."Private Value");
                EinvoiceHttpHeader.Add('Content-Type', 'application/json');
                EinvoiceHttpHeader.Add('IP', EInvoiceSetUp."Private IP");
                EinvoiceHttpRequest.Content := EinvoiceHttpContent;
                EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Way Bill URL");
                EinvoiceHttpRequest.Method := 'POST';
                if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                    EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
                    JResultObject.ReadFrom(ResultMessage);
                    Char13 := 13;
                    Char10 := 10;
                    NewLine := FORMAT(Char10) + FORMAT(Char13);
                    ErrorLogMessage += 'Time :' + format(CurrentDateTime) + NewLine + '-----------------------------------------------------------' + NewLine
              + ResultMessage + NewLine + '-----------------------------------------------------------';

                    if JResultObject.Get('MessageId', JResultToken) then
                        if JResultToken.AsValue().AsInteger() = 1 then begin
                            if JResultObject.Get('Message', JResultToken) then;
                            Message(Format(JResultToken));
                        end else
                            if JResultObject.Get('Message', JResultToken) then
                                Message(Format(JResultToken));

                    if JResultObject.Get('Data', JResultToken) then
                        if JResultToken.IsArray then begin
                            JResultToken.WriteTo(OutputMessage);
                            JResultArray.ReadFrom(OutputMessage);
                            if JResultArray.Get(0, JOutputToken) then begin
                                if JOutputToken.IsObject then begin
                                    JOutputToken.WriteTo(OutputMessage);
                                    JOutputObject.ReadFrom(OutputMessage);
                                end;
                            end;

                            if JOutputObject.Get('Remarks', JOutputToken) then
                                Remarks := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('Status', JOutputToken) then
                                Status := JOutputToken.AsValue().AsText();
                            if JOutputObject.Get('validUpto', JOutputToken) then
                                ValidUpto := JOutputToken.AsValue().AsText();
                        end;
                end else
                    Message('Generation Invoice Detail Failed!!');
                ROBOOutput."Eway Bill Valid Till" := ValidUpto;
                ROBOOutput.MODIFY;

            END;
        END;
    end;

    procedure DownloadEwayBillPDF(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        ROBOOutput: Record 50014;
        URLtext: Text;
        Instr: InStream;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpResponse: HttpResponseMessage;
        EinvoiceHttpClient: HttpClient;
        FileName: text;
        Location: Record Location;
        EInvoiceSetup: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetup.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDFIRST THEN BEGIN
            DtldGSTLedgerEntry.RESET;
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
            DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
            IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN
                ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                ROBOSetup.TestField("User Name");
                ROBOSetup.TestField(Password);
                /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                ROBOSetup.TESTFIELD("Eway Private Key");
                ROBOSetup.TESTFIELD("Eway Private Value");
                ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                ROBOSetup.TESTFIELD(ROBOSetup.Password);
                ROBOSetup.TESTFIELD(ROBOSetup."URL E-Way");
                ROBOSetup.TESTFIELD(ROBOSetup."Eway PDF Path");
 */ // 15800
    // 15800 Open For Production  URLtext := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + DtldGSTLedgerEntry."Location  Reg. No." + '&EWBNO=' + ROBOOutput."Eway Bill No" + '&action=GETEWAYBILL';
                URLtext := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + '05AAACE1268K1ZR' + '&EWBNO=' + ROBOOutput."Eway Bill No" + '&action=GETEWAYBILL';
                /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
                   EwayPDFMessageID := EWayAPI.DownloadEwayBillPdf(URLtext,
                                                ROBOSetup."Eway Private Key",
                                                ROBOSetup."Eway Private Value",
                                                ROBOSetup.IPAddress,
                                                ROBOSetup."Error File Save Path",
                                                ROBOSetup."Eway PDF Path",ROBOOutput."Eway Bill No");
                //12887 commneted ASSERTERROR ERROR coming IN cu67 compilation*/


                //  PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
                // PostUrl := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
                EinvoiceHttpRequest.SetRequestUri(URLtext);
                EinvoiceHttpHeader.Clear();
                EinvoiceHttpRequest.GetHeaders(EinvoiceHttpHeader);
                EinvoiceHttpRequest.Method := 'GET';
                EinvoiceHttpHeader.Add('accept', 'application/json');
                EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEKEY', EInvoiceSetup."Private Key");
                EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEVALUE', EInvoiceSetup."Private Value");
                EinvoiceHttpHeader.TryAddWithoutValidation('IP', EInvoiceSetup."Private IP");
                EinvoiceHttpHeader.TryAddWithoutValidation('Gstin', Location."GST Registration No.");
                if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
                    EinvoiceHttpResponse.Content.ReadAs(Instr);
                    FileName := ROBOOutput."Eway Bill No" + '.pdf';
                    DownloadFromStream(Instr, 'Export', '', 'All Files (*.*)|*.*', FileName);
                    //   Hyperlink('C:/Users/15800/Downloads/701303098188.pdf');
                end;
            END;
        END;
    end;

    local procedure GetTotalInvValue(DocNo: Code[20]): Decimal
    var
        CustLedgerEntry: Record 21;
    begin
        CustLedgerEntry.SETRANGE("Document No.", DocNo);
        CustLedgerEntry.SETAUTOCALCFIELDS("Original Amount", "Original Amt. (LCY)");
        CustLedgerEntry.FINDFIRST;
        EXIT(ABS(CustLedgerEntry."Original Amt. (LCY)"))
    end;

    local procedure GetAssValue(DocNo: Code[20]; DocLineNo: Integer): Decimal
    var
        DetailedGSTLedger: Record "Detailed GST Ledger Entry";
    begin
        DetailedGSTLedger.SetRange("Document No.", DocNo);
        DetailedGSTLedger.SetRange("Document Line No.", DocLineNo);
        if DetailedGSTLedger.FindFirst() then
            exit(DetailedGSTLedger."GST Base Amount");
    end;

    local procedure GetTCSAmount(DocNo: Code[20]) TCSAmt: Decimal
    var
        TCSEntry: Record "TCS Entry";
    begin
        TCSEntry.Reset();
        TCSEntry.SetRange("Document No.", DocNo);
        if TCSEntry.FindSet() then
            repeat
                TCSAmt += TCSEntry."Total TCS Including SHE CESS";
            until TCSEntry.Next() = 0;
        EXIT(TCSAmt);
    end;

    local procedure GetStrucDisc(DocNo: Code[20]): Decimal
    begin
        // PstdStrLineDtls.SETRANGE("Invoice No.",DocNo);
        // PstdStrLineDtls.SETRANGE("Tax/Charge Type",PstdStrLineDtls."Tax/Charge Type"::Charges);
        // PstdStrLineDtls.SETFILTER("Tax/Charge Group",'<>%1','FREIGHT');
        // IF PstdStrLineDtls.FINDSET THEN
        // REPEAT
        //  DiscAmt += PstdStrLineDtls."Amount (LCY)";
        // UNTIL PstdStrLineDtls.NEXT = 0;

        // EXIT(DiscAmt);
    end;

    local procedure GetFreight(DocNo: Code[20]) FreightAmt: Decimal
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
        EXIT(-FreightAmt);// Changes For Production FreightAmt Replaced By
    end;

    procedure DownloadEWayBillInvoice(VAR SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        Instr: InStream;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpResponse: HttpResponseMessage;
        EinvoiceHttpClient: HttpClient;
        FileName: text;
        Location: Record Location;
        PostUrl: text;
        EInvoiceSetup: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetup.Get();
        Location.RESET;
        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        //  PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        PostUrl := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        EinvoiceHttpRequest.SetRequestUri(PostUrl);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpRequest.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpRequest.Method := 'GET';
        EinvoiceHttpHeader.Add('accept', 'application/json');
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.TryAddWithoutValidation('IP', EInvoiceSetup."Private IP");
        EinvoiceHttpHeader.TryAddWithoutValidation('Gstin', Location."GST Registration No.");
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(Instr);
            FileName := SalesInvoiceHeader."E-Way Bill No." + '.pdf';
            DownloadFromStream(Instr, 'Export', '', 'All Files (*.*)|*.*', FileName);
            //   Hyperlink('C:/Users/15800/Downloads/701303098188.pdf');
        end;
    end;
}
