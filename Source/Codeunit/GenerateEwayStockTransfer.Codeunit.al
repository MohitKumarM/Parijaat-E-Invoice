codeunit 50500 "GenerateEwayStockTranfr Cloud"
{
    trigger OnRun()
    begin
    end;

    var
        CompInfo: Record 79;
        Char10: Char;
        Char13: Char;
        NewLine: Text;
        ErrorLogMessage: Text;

        ROBOSetup: Record "GST Registration Nos.";
        GlbTextVar: Text;
        EwayBillNoErr: Label 'Eway Bill No. has not been generated. Update Part A to generate Eway bill first.';

    procedure GenerateInvoiceDetails(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        TransShipment: Record 5744;
        State: Record State;
        Country: Record 9;
        TrFromLocation: Record 14;
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        AlternativeAdrees: Record "Alternative Address";
        CessVal: Decimal;
        CGSTVal: Decimal;
        IGSTVal: Decimal;
        SGSTVal: Decimal;
        CessNonAdVal: Decimal;
        StCessVal: Decimal;
        TotalInvVal: Decimal;
        AssVal: Decimal;
        PreviousLineNo: Integer;
        Remarks: Text;
        Status: Text;
        Transporter: Record 23;
        ReturnMsg: Label 'Status : %1\ %2';
        TrToLocation: Record 14;
        TransAdd: Text[250];
        TransFAdd: Text[250];
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
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        //ROBOAPICalls.CheckIfCancelled(DocNo);

        TransShipment.GET(DocNo);
        TrToLocation.GET(TransShipment."Transfer-to Code");
        TrFromLocation.GET(TransShipment."Transfer-from Code");

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
            WriteToGlbTextVar('GENERATOR_GSTIN', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);

            WriteToGlbTextVar('TRANSACTION_TYPE', 'Outward', 0, TRUE);
            WriteToGlbTextVar('TRANSACTION_SUB_TYPE', 'Supply', 0, TRUE);
            WriteToGlbTextVar('SUPPLY_TYPE', '', 0, TRUE); // 15800
            WriteToGlbTextVar('DOC_TYPE', 'Tax Invoice', 0, TRUE);
            WriteToGlbTextVar('DOC_NO', FORMAT(TransShipment."No."), 0, TRUE);
            WriteToGlbTextVar('DOC_DATE', FORMAT(TransShipment."Posting Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);

            WriteToGlbTextVar('CONSIGNOR_GSTIN_NO', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);
            WriteToGlbTextVar('CONSIGNOR_LEGAL_NAME', CompInfo.Name, 0, TRUE);
            WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', DtldGSTLedgerEntry."Buyer/Seller Reg. No.", 0, TRUE);

            WriteToGlbTextVar('CONSIGNEE_LEGAL_NAME', TransShipment."Transfer-from Name", 0, TRUE);
            //WriteToGlbTextVar('SHIP_ADDRESS_LINE1',TransShipment."Transfer-to Address",0,TRUE);
            TransAdd := TransShipment."Transfer-to Address" + ', ' + TransShipment."Transfer-to Address 2";
            WriteToGlbTextVar('SHIP_ADDRESS_LINE1', TransAdd, 0, TRUE);
            State.GET(TrToLocation."State Code");
            WriteToGlbTextVar('SHIP_STATE', State.Description, 0, TRUE);


            //  WriteToGlbTextVar('SHIP_CITY_NAME',TransShipment."Transfer-to City",0,TRUE);
            //WriteToGlbTextVar('SHIP_CITY_NAME',TrFromLocation.City,0,TRUE);
            WriteToGlbTextVar('SHIP_CITY_NAME', TransShipment."Transfer-to City", 0, TRUE);
            WriteToGlbTextVar('SHIP_PIN_CODE', TransShipment."Transfer-to Post Code", 0, TRUE);


            Country.GET(TransShipment."Trsf.-to Country/Region Code");
            WriteToGlbTextVar('SHIP_COUNTRY', FORMAT(Country.Name), 0, TRUE);

            //WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1',TrFromLocation.Address,0,TRUE);
            if TransShipment.Alternative <> '' then begin
                AlternativeAdrees.Reset();
                AlternativeAdrees.SetRange("Employee No.", 'PIPL');
                AlternativeAdrees.SetRange(Code, TransShipment.Alternative);
                if AlternativeAdrees.FindFirst() then begin
                    WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', AlternativeAdrees.Name + ' ,' + AlternativeAdrees.Address + ' ,' + AlternativeAdrees."Address 2", 0, TRUE);
                    State.GET(AlternativeAdrees.EIN_State);
                    WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);
                    WriteToGlbTextVar('ORIGIN_CITY_NAME', AlternativeAdrees.City, 0, TRUE);
                    WriteToGlbTextVar('ORIGIN_PIN_CODE', AlternativeAdrees."Post Code", 0, TRUE);
                end;
            end else begin
                TransFAdd := TrFromLocation.Address + ', ' + TrFromLocation."Address 2";
                WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', TransFAdd, 0, TRUE);
                State.GET(TrFromLocation."State Code");
                WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);
                WriteToGlbTextVar('ORIGIN_CITY_NAME', TrFromLocation.City, 0, TRUE);
                WriteToGlbTextVar('ORIGIN_PIN_CODE', TrFromLocation."Post Code", 0, TRUE);
            end;
            //IF TransportMethod.GET(TransShipment."Transport Method") THEN
            //WriteToGlbTextVar('TRANSPORT_MODE','null',0,TRUE);
            WriteToGlbTextVar('TRANSPORT_MODE', 'null', 1, TRUE);
            WriteToGlbTextVar('VEHICLE_TYPE', 'null', 1, TRUE);
            //    IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::Regular THEN
            //      WriteToGlbTextVar('VEHICLE_TYPE',FORMAT('Normal'),0,TRUE)
            //    ELSE
            //      WriteToGlbTextVar('VEHICLE_TYPE',FORMAT('Over Dimensional Cargo'),0,TRUE);

            IF Transporter.GET(TransShipment."Transporter Code") THEN
                WriteToGlbTextVar('TRANSPORTER_ID_GSTIN', Transporter."GST Registration No.", 0, TRUE);

            WriteToGlbTextVar('APPROXIMATE_DISTANCE', FORMAT(TransShipment."Distance (Km)"), 1, TRUE);
            WriteToGlbTextVar('TRANS_DOC_NO', TransShipment."LR/RR No.", 0, TRUE);
            WriteToGlbTextVar('TRANS_DOC_DATE', FORMAT(TransShipment."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
            WriteToGlbTextVar('VEHICLE_NO', TransShipment."Vehicle No.", 0, TRUE);

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

                    IF DtldGSTLedgEntry2."GST Component Code" = 'CESS' THEN
                        CessVal += ABS(DtldGSTLedgEntry2."GST Amount")
                    ELSE
                        IF DtldGSTLedgEntry2."GST Component Code" = 'CGST' THEN
                            CGSTVal += ABS(DtldGSTLedgEntry2."GST Amount")
                        ELSE
                            IF DtldGSTLedgEntry2."GST Component Code" = 'IGST' THEN
                                IGSTVal += ABS(DtldGSTLedgEntry2."GST Amount")
                            ELSE
                                IF DtldGSTLedgEntry2."GST Component Code" = 'SGST' THEN
                                    SGSTVal += ABS(DtldGSTLedgEntry2."GST Amount");
                UNTIL DtldGSTLedgEntry2.NEXT = 0;

            DtldGSTLedgEntry2.RESET;
            DtldGSTLedgEntry2.SETRANGE("Entry Type", DtldGSTLedgEntry2."Entry Type"::"Initial Entry");
            DtldGSTLedgEntry2.SETRANGE("Document No.", DtldGSTLedgerEntry."Document No.");
            IF DtldGSTLedgerEntry."Item Charge Entry" THEN BEGIN
                DtldGSTLedgEntry2.SETRANGE("Original Invoice No.", DtldGSTLedgerEntry."Original Invoice No.");
                // 15800   DtldGSTLedgEntry2.SETRANGE("Item Charge Assgn. Line No.", DtldGSTLedgerEntry."Item Charge Assgn. Line No.");
            END;
            IF DtldGSTLedgEntry2.FINDSET THEN
                REPEAT
                    IF DtldGSTLedgEntry2."GST Component Code" = 'CESS' THEN
                        CessNonAdVal += ABS(DtldGSTLedgEntry2."GST Amount");
                UNTIL DtldGSTLedgEntry2.NEXT = 0;
            StCessVal := CessNonAdVal;

            TotalInvVal := AssVal + CGSTVal + SGSTVal + IGSTVal + CessVal + CessNonAdVal + StCessVal;

            WriteToGlbTextVar('CGST_AMOUNT', FORMAT(ABS(CGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('SGST_AMOUNT', FORMAT(ABS(SGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('IGST_AMOUNT', FORMAT(ABS(IGSTVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('CESS_AMOUNT', FORMAT(ABS(CessVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('TOTAL_TAXABLE_VALUE', FORMAT(ABS(AssVal), 0, 2), 1, TRUE);
            WriteToGlbTextVar('OTHER_VALUE', '0', 1, TRUE);
            WriteToGlbTextVar('TOTAL_INVOICE_VALUE', FORMAT(ABS(TotalInvVal), 0, 2), 1, TRUE);

            GlbTextVar += '"Items" : [';
            WriteItemListEWB(DtldGSTLedgerEntry);
            GlbTextVar += ']';
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';

            /* ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
            ROBOSetup.TESTFIELD("URL E-Way");
             */
            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("E-Invoice User Name");
            ROBOSetup.TestField(Password);
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
        END;
    end;

    procedure GenerateInvoiceDetailsInter(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
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
        TransShipment: Record 5744;
        State: Record State;
        Country: Record 9;
        TrFromLocation: Record 14;
        TransportMethod: Record 259;

        CessVal: Decimal;
        CGSTVal: Decimal;
        IGSTVal: Decimal;
        SGSTVal: Decimal;
        CessNonAdVal: Decimal;
        StCessVal: Decimal;
        TotalInvVal: Decimal;
        AssVal: Decimal;
        PreviousLineNo: Integer;
        Remarks: Text;
        Status: Text;
        ReturnMsg: Label 'Status : %1\ %2';
        TrToLocation: Record 14;
        EInvoiceOutput: Record 50014;
        Transporter: Record 23;
        TransAdd1: Text[250];
        TransFAdd1: Text[250];
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        //ROBOAPICalls.CheckIfCancelled(DocNo);

        TransShipment.GET(DocNo);
        TrToLocation.GET(TransShipment."Transfer-to Code");
        TrFromLocation.GET(TransShipment."Transfer-from Code");

        CLEAR(CessVal);
        CLEAR(CGSTVal);
        CLEAR(IGSTVal);
        CLEAR(SGSTVal);
        CLEAR(CessNonAdVal);
        CLEAR(StCessVal);
        CLEAR(TotalInvVal);
        CLEAR(AssVal);
        CLEAR(PreviousLineNo);

        GlbTextVar := '';
        //Write Common Details
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'INVOICE', 0, TRUE);
        GlbTextVar += '"data" : [';
        GlbTextVar += '{';
        WriteToGlbTextVar('GENERATOR_GSTIN', TrFromLocation."GST Registration No.", 0, TRUE);

        //WriteToGlbTextVar('SUPPLY_TYPE','Regular',0,TRUE);//Commented by LFS_NG
        WriteToGlbTextVar('SUPPLY_TYPE', '', 0, TRUE);//Added by LFS_NG
                                                      // WriteToGlbTextVar('TRANSACTION_SUB_TYPE','For Own Use',0,TRUE);//Commented by LFS_NG
        WriteToGlbTextVar('TRANSACTION_SUB_TYPE', 'Recipient not known', 0, TRUE);//Added by LFS_NG
                                                                                  //WriteToGlbTextVar('TRANSACTION_SUB_TYPE','Others - Delivery Challan',0,TRUE);//Added by LFS_NG
                                                                                  //WriteToGlbTextVar('DOC_TYPE','CHL',0,TRUE);// Commented by LFS_NG
        WriteToGlbTextVar('DOC_TYPE', 'Delivery Challan', 0, TRUE);//Added by LFS_NG
        WriteToGlbTextVar('TRANSACTION_TYPE', 'Outward', 0, TRUE);
        WriteToGlbTextVar('DOC_NO', FORMAT(TransShipment."No."), 0, TRUE);
        WriteToGlbTextVar('DOC_DATE', FORMAT(TransShipment."Posting Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
        WriteToGlbTextVar('CONSIGNOR_GSTIN_NO', TrFromLocation."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('CONSIGNOR_LEGAL_NAME', CompInfo.Name, 0, TRUE);
        WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', TrToLocation."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('CONSIGNEE_LEGAL_NAME', TransShipment."Transfer-from Name", 0, TRUE);
        //WriteToGlbTextVar('SHIP_ADDRESS_LINE1',TransShipment."Transfer-to Address",0,TRUE);
        TransAdd1 := TransShipment."Transfer-to Address" + ', ' + TransShipment."Transfer-to Address 2";
        WriteToGlbTextVar('SHIP_ADDRESS_LINE1', TransAdd1, 0, TRUE);
        State.GET(TrToLocation."State Code");
        WriteToGlbTextVar('SHIP_STATE', State.Description, 0, TRUE);

        //WriteToGlbTextVar('SHIP_CITY_NAME',TransShipment."Transfer-to City",0,TRUE);
        WriteToGlbTextVar('SHIP_CITY_NAME', TrToLocation.City, 0, TRUE);
        //WriteToGlbTextVar('SHIP_PIN_CODE',TransShipment."Transfer-to Post Code",0,TRUE);
        WriteToGlbTextVar('SHIP_PIN_CODE', TrToLocation."Post Code", 0, TRUE);

        Country.GET(TransShipment."Trsf.-to Country/Region Code");
        WriteToGlbTextVar('SHIP_COUNTRY', FORMAT(Country.Name), 0, TRUE);
        //WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1',TrFromLocation.Address,0,TRUE);
        TransFAdd1 := TrFromLocation.Address + ', ' + TrFromLocation."Address 2";
        WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', TransFAdd1, 0, TRUE);

        State.GET(TrFromLocation."State Code");
        WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);

        WriteToGlbTextVar('ORIGIN_CITY_NAME', TrFromLocation.City, 0, TRUE);
        WriteToGlbTextVar('ORIGIN_PIN_CODE', TrFromLocation."Post Code", 0, TRUE);

        IF TransportMethod.GET(TransShipment."Transport Method") THEN
            WriteToGlbTextVar('TRANSPORT_MODE', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
        //LFS-NG
        //WriteToGlbTextVar('TRANSPORT_MODE',FORMAT(TransShipment."Mode of Transport"),0,TRUE);//LFS-NG
        IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::Regular THEN
            WriteToGlbTextVar('VEHICLE_TYPE', FORMAT('Normal'), 0, TRUE)
        ELSE
            IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::ODC THEN
                WriteToGlbTextVar('VEHICLE_TYPE', FORMAT('Over Dimensional Cargo'), 0, TRUE)
            ELSE
                IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::" " THEN
                    WriteToGlbTextVar('VEHICLE_TYPE', 'null', 1, TRUE);
        //IF ShippingAgent.GET(TransShipment."Shipping Agent Code") THEN
        //  WriteToGlbTextVar('TRANSPORTER_ID_GSTIN',ShippingAgent."GST Registration No.",0,TRUE);
        IF Transporter.GET(TransShipment."Transporter Code") THEN
            WriteToGlbTextVar('TRANSPORTER_ID_GSTIN', Transporter."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('APPROXIMATE_DISTANCE', FORMAT(TransShipment."Distance (Km)"), 1, TRUE);
        IF TransShipment."LR/RR No." <> '' THEN
            WriteToGlbTextVar('TRANS_DOC_NO', TransShipment."LR/RR No.", 0, TRUE)
        ELSE
            WriteToGlbTextVar('TRANS_DOC_NO', 'null', 1, TRUE);
        IF TransShipment."LR/RR Date" <> 0D THEN
            WriteToGlbTextVar('TRANS_DOC_DATE', FORMAT(TransShipment."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE)
        ELSE
            WriteToGlbTextVar('TRANS_DOC_DATE', 'null', 1, TRUE);

        IF TransShipment."Vehicle No." <> '' THEN
            WriteToGlbTextVar('VEHICLE_NO', TransShipment."Vehicle No.", 0, TRUE)
        ELSE
            WriteToGlbTextVar('VEHICLE_NO', 'null', 1, TRUE);
        TotalInvVal := GetTotDCValue(TransShipment."No.");


        WriteToGlbTextVar('CGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('SGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('IGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('CESS_AMOUNT', 'null', 1, TRUE);
        //   WriteToGlbTextVar('TOTAL_TAXABLE_VALUE','()null',1,TRUE);
        WriteToGlbTextVar('TOTAL_TAXABLE_VALUE', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('OTHER_VALUE', '0', 1, TRUE);
        WriteToGlbTextVar('TOTAL_INVOICE_VALUE', FORMAT(ABS(TotalInvVal), 0, 2), 1, TRUE);

        GlbTextVar += '"Items" : [';
        WriteItemListEWBInter(DtldGSTLedgerEntry, DocNo);
        GlbTextVar += ']';
        GlbTextVar += '}';
        GlbTextVar += ']';
        GlbTextVar += '}';
        /*  ROBOSetup.GET(TrFromLocation."GST Registration No.");
         ROBOSetup.TESTFIELD("Eway Private Key");
         ROBOSetup.TESTFIELD("Eway Private Value");
         ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
         ROBOSetup.TESTFIELD(ROBOSetup.user_name);
         ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
         ROBOSetup.TESTFIELD(ROBOSetup.Password);
         ROBOSetup.TESTFIELD("URL E-Way");
         */
        ROBOSetup.GET(TrFromLocation."GST Registration No.");
        ROBOSetup.TestField("E-Invoice User Name");
        ROBOSetup.TestField(Password);
        MESSAGE(GlbTextVar);
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
                end;
        end else
            Message('Generation Invoice Detail Failed!!');
        EInvoiceOutput.RESET;
        EInvoiceOutput.SETRANGE("Document No.", DocNo);
        IF EInvoiceOutput.ISEMPTY THEN BEGIN
            EInvoiceOutput."Document Type" := EInvoiceOutput."Document Type"::"Transfer Shipment";
            EInvoiceOutput."Document No." := DocNo;
            EInvoiceOutput.INSERT;
        END;

    end;

    procedure GenerateInvoiceDetailsJB(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",Transfer,"Finance Charge Memo",Reminder,Refund,"Transfer Shipment","Transfer Receipt")
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
        TransShipment: Record 5744;
        State: Record State;
        Country: Record 9;
        TrFromLocation: Record 14;
        TransportMethod: Record 259;

        CessVal: Decimal;
        CGSTVal: Decimal;
        IGSTVal: Decimal;
        SGSTVal: Decimal;
        CessNonAdVal: Decimal;
        StCessVal: Decimal;
        TotalInvVal: Decimal;
        AssVal: Decimal;
        PreviousLineNo: Integer;
        Remarks: Text;
        Status: Text;
        ReturnMsg: Label 'Status : %1\ %2';
        TrToLocation: Record 14;
        EInvoiceOutput: Record 50014;
        Transporter: Record 23;
        TransAdd1: Text[250];
        TransFAdd1: Text[250];
    begin
        EInvoiceSetUp.Get();
        EInvoiceSetUp.TestField("Private Key");
        EInvoiceSetUp.TestField("Private Value");
        EInvoiceSetUp.TestField("Private IP");
        EInvoiceSetUp.TestField("E-Way Bill URL");
        CompInfo.GET;
        CompInfo.TESTFIELD(CompInfo."E-Mail");

        //ROBOAPICalls.CheckIfCancelled(DocNo);

        TransShipment.GET(DocNo);
        TrToLocation.GET(TransShipment."Transfer-to Code");
        TrFromLocation.GET(TransShipment."Transfer-from Code");

        CLEAR(CessVal);
        CLEAR(CGSTVal);
        CLEAR(IGSTVal);
        CLEAR(SGSTVal);
        CLEAR(CessNonAdVal);
        CLEAR(StCessVal);
        CLEAR(TotalInvVal);
        CLEAR(AssVal);
        CLEAR(PreviousLineNo);

        GlbTextVar := '';
        //Write Common Details
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'INVOICE', 0, TRUE);
        GlbTextVar += '"data" : [';
        GlbTextVar += '{';
        WriteToGlbTextVar('GENERATOR_GSTIN', TrFromLocation."GST Registration No.", 0, TRUE);

        //WriteToGlbTextVar('SUPPLY_TYPE','Regular',0,TRUE);//Commented by LFS_NG
        WriteToGlbTextVar('SUPPLY_TYPE', '', 0, TRUE);//Added by LFS_NG
                                                      // WriteToGlbTextVar('TRANSACTION_SUB_TYPE','For Own Use',0,TRUE);//Commented by LFS_NG
        WriteToGlbTextVar('TRANSACTION_SUB_TYPE', 'JOB WORK', 0, TRUE);//Added by LFS_NG
                                                                       //WriteToGlbTextVar('TRANSACTION_SUB_TYPE','Others - Delivery Challan',0,TRUE);//Added by LFS_NG
                                                                       //WriteToGlbTextVar('DOC_TYPE','CHL',0,TRUE);// Commented by LFS_NG
        WriteToGlbTextVar('DOC_TYPE', 'Delivery Challan', 0, TRUE);//Added by LFS_NG
        WriteToGlbTextVar('TRANSACTION_TYPE', 'Outward', 0, TRUE);
        WriteToGlbTextVar('DOC_NO', FORMAT(TransShipment."No."), 0, TRUE);
        WriteToGlbTextVar('DOC_DATE', FORMAT(TransShipment."Posting Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
        WriteToGlbTextVar('CONSIGNOR_GSTIN_NO', TrFromLocation."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('CONSIGNOR_LEGAL_NAME', CompInfo.Name, 0, TRUE);
        WriteToGlbTextVar('CONSIGNEE_GSTIN_NO', TrToLocation."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('CONSIGNEE_LEGAL_NAME', TransShipment."Transfer-from Name", 0, TRUE);
        //WriteToGlbTextVar('SHIP_ADDRESS_LINE1',TransShipment."Transfer-to Address",0,TRUE);
        TransAdd1 := TransShipment."Transfer-to Address" + ', ' + TransShipment."Transfer-to Address 2";
        WriteToGlbTextVar('SHIP_ADDRESS_LINE1', TransAdd1, 0, TRUE);
        State.GET(TrToLocation."State Code");
        WriteToGlbTextVar('SHIP_STATE', State.Description, 0, TRUE);

        //WriteToGlbTextVar('SHIP_CITY_NAME',TransShipment."Transfer-to City",0,TRUE);
        WriteToGlbTextVar('SHIP_CITY_NAME', TrToLocation.City, 0, TRUE);
        //WriteToGlbTextVar('SHIP_PIN_CODE',TransShipment."Transfer-to Post Code",0,TRUE);
        WriteToGlbTextVar('SHIP_PIN_CODE', TrToLocation."Post Code", 0, TRUE);

        Country.GET(TransShipment."Trsf.-to Country/Region Code");
        WriteToGlbTextVar('SHIP_COUNTRY', FORMAT(Country.Name), 0, TRUE);
        //WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1',TrFromLocation.Address,0,TRUE);
        TransFAdd1 := TrFromLocation.Address + ', ' + TrFromLocation."Address 2";
        WriteToGlbTextVar('ORIGIN_ADDRESS_LINE1', TransFAdd1, 0, TRUE);

        State.GET(TrFromLocation."State Code");
        WriteToGlbTextVar('ORIGIN_STATE', State.Description, 0, TRUE);

        WriteToGlbTextVar('ORIGIN_CITY_NAME', TrFromLocation.City, 0, TRUE);
        WriteToGlbTextVar('ORIGIN_PIN_CODE', TrFromLocation."Post Code", 0, TRUE);

        IF TransportMethod.GET(TransShipment."Transport Method") THEN
            WriteToGlbTextVar('TRANSPORT_MODE', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
        //LFS-NG
        //WriteToGlbTextVar('TRANSPORT_MODE',FORMAT(TransShipment."Mode of Transport"),0,TRUE);//LFS-NG
        IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::Regular THEN
            WriteToGlbTextVar('VEHICLE_TYPE', FORMAT('Normal'), 0, TRUE)
        ELSE
            IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::ODC THEN
                WriteToGlbTextVar('VEHICLE_TYPE', FORMAT('Over Dimensional Cargo'), 0, TRUE)
            ELSE
                IF TransShipment."Vehicle Type" = TransShipment."Vehicle Type"::" " THEN
                    WriteToGlbTextVar('VEHICLE_TYPE', 'null', 1, TRUE);
        //IF ShippingAgent.GET(TransShipment."Shipping Agent Code") THEN
        //  WriteToGlbTextVar('TRANSPORTER_ID_GSTIN',ShippingAgent."GST Registration No.",0,TRUE);
        IF Transporter.GET(TransShipment."Transporter Code") THEN
            WriteToGlbTextVar('TRANSPORTER_ID_GSTIN', Transporter."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('APPROXIMATE_DISTANCE', FORMAT(TransShipment."Distance (Km)"), 1, TRUE);
        IF TransShipment."LR/RR No." <> '' THEN
            WriteToGlbTextVar('TRANS_DOC_NO', TransShipment."LR/RR No.", 0, TRUE)
        ELSE
            WriteToGlbTextVar('TRANS_DOC_NO', 'null', 1, TRUE);
        IF TransShipment."LR/RR Date" <> 0D THEN
            WriteToGlbTextVar('TRANS_DOC_DATE', FORMAT(TransShipment."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE)
        ELSE
            WriteToGlbTextVar('TRANS_DOC_DATE', 'null', 1, TRUE);

        IF TransShipment."Vehicle No." <> '' THEN
            WriteToGlbTextVar('VEHICLE_NO', TransShipment."Vehicle No.", 0, TRUE)
        ELSE
            WriteToGlbTextVar('VEHICLE_NO', 'null', 1, TRUE);
        TotalInvVal := GetTotDCValue(TransShipment."No.");


        WriteToGlbTextVar('CGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('SGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('IGST_AMOUNT', 'null', 1, TRUE);
        WriteToGlbTextVar('CESS_AMOUNT', 'null', 1, TRUE);
        //   WriteToGlbTextVar('TOTAL_TAXABLE_VALUE','()null',1,TRUE);
        WriteToGlbTextVar('TOTAL_TAXABLE_VALUE', FORMAT(0), 1, TRUE);
        WriteToGlbTextVar('OTHER_VALUE', '0', 1, TRUE);
        WriteToGlbTextVar('TOTAL_INVOICE_VALUE', FORMAT(ABS(TotalInvVal), 0, 2), 1, TRUE);

        GlbTextVar += '"Items" : [';
        WriteItemListEWBInter(DtldGSTLedgerEntry, DocNo);
        GlbTextVar += ']';
        GlbTextVar += '}';
        GlbTextVar += ']';
        GlbTextVar += '}';
        /*  ROBOSetup.GET(TrFromLocation."GST Registration No.");
         ROBOSetup.TESTFIELD("Eway Private Key");
         ROBOSetup.TESTFIELD("Eway Private Value");
         ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
         ROBOSetup.TESTFIELD(ROBOSetup.user_name);
         ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
         ROBOSetup.TESTFIELD(ROBOSetup.Password);
         ROBOSetup.TESTFIELD("URL E-Way");
         */
        ROBOSetup.GET(TrFromLocation."GST Registration No.");
        ROBOSetup.TestField("E-Invoice User Name");
        ROBOSetup.TestField(Password);
        MESSAGE(GlbTextVar);
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
                end;
        end else
            Message('Generation Invoice Detail Failed!!');
        EInvoiceOutput.RESET;
        EInvoiceOutput.SETRANGE("Document No.", DocNo);
        IF EInvoiceOutput.ISEMPTY THEN BEGIN
            EInvoiceOutput."Document Type" := EInvoiceOutput."Document Type"::"Transfer Shipment";
            EInvoiceOutput."Document No." := DocNo;
            EInvoiceOutput.INSERT;
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
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                if DGLInfo.Get(DtldGSTLedgEntry2."Entry No.") then;
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
                DGLInfo.SETRANGE(DGLInfo."Item Charge Assgn. Line No.", TaxProEInvoicingBuffer."Item Charge Line No.");
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
                    WriteToGlbTextVar('CESS_RATE', "CESS%", 1, TRUE);
                    WriteToGlbTextVar('CESS_NONADVOL', FORMAT(ABS(0), 0, 2), 1, TRUE);
                    IF DGLInfo.Get(DtldGSTLedgEntry2."Entry No.") then;
                    Item.GET(DtldGSTLedgEntry2."No.");
                    UnitofMeasure.GET(DGLInfo.UOM);
                    WriteToGlbTextVar('ITEM_NAME', Item.Description, 0, TRUE);

                    WriteToGlbTextVar('HSN_CODE', DtldGSTLedgEntry2."HSN/SAC Code", 0, TRUE);

                    WriteToGlbTextVar('UOM', UnitofMeasure."UOM For E Invoicing", 0, TRUE); // 15800

                    WriteToGlbTextVar('QUANTITY', FORMAT(ABS(DtldGSTLedgEntry2.Quantity), 0, 2), 1, TRUE);

                    WriteToGlbTextVar('TAXABLE_VALUE', FORMAT(ABS((DtldGSTLedgEntry2."GST Base Amount")), 0, 2), 1, FALSE);

                    IF LineCnt <> TotalLines THEN
                        GlbTextVar += '},'
                    ELSE
                        GlbTextVar += '}'
                END;
            UNTIL TaxProEInvoicingBuffer.NEXT = 0;
    end;

    local procedure WriteItemListEWBInter(DtldGSTLedgEntry: Record "Detailed GST Ledger Entry"; DocNo: Code[20])
    var
        DtldGSTLedgEntry2: Record "Detailed GST Ledger Entry";
        TaxProEInvoicingBuffer: Record 50013 temporary;
        Item: Record 27;
        UnitofMeasure: Record 204;
        TransferShipmentLine: Record 5745;
        "CGST%": Text;
        "SGST%": Text;
        "IGST%": Text;
        "CESS%": Text;
        TotalLines: Integer;
        LineCnt: Integer;
        DGLInfo: Record "Detailed GST Ledger Entry Info";
    begin
        DtldGSTLedgEntry2.RESET;
        DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.", DtldGSTLedgEntry."Document No.");
        IF DtldGSTLedgEntry2.FINDSET THEN
            REPEAT
                if DGLInfo.Get(DtldGSTLedgEntry2."Entry No.") then;
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
        "IGST%" := FORMAT(0);
        "CESS%" := 'null';
        "CGST%" := 'null';

        // TaxProEInvoicingBuffer.RESET;
        // IF TaxProEInvoicingBuffer.FINDSET THEN REPEAT
        //   LineCnt += 1;
        //   DtldGSTLedgEntry2.RESET;
        //   DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document No.",TaxProEInvoicingBuffer."Document No.");
        //   DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Document Line No.",TaxProEInvoicingBuffer."Document Line No.");
        //   DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Original Invoice No.",TaxProEInvoicingBuffer."Original Invoice No.");
        //   DtldGSTLedgEntry2.SETRANGE(DtldGSTLedgEntry2."Item Charge Assgn. Line No.",TaxProEInvoicingBuffer."Item Charge Line No.");
        //   IF DtldGSTLedgEntry2.FINDFIRST THEN BEGIN
        //      "GST%" := 0;

        //
        //      DtldGSTLedgEntry3.RESET;
        //      DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document No.",DtldGSTLedgEntry2."Document No.");
        //      DtldGSTLedgEntry3.SETRANGE(DtldGSTLedgEntry3."Document Line No.",DtldGSTLedgEntry2."Document Line No.");
        //      IF DtldGSTLedgEntry3.FINDSET THEN REPEAT
        //         IF GSTComponent.GET(DtldGSTLedgEntry3."GST Component Code") THEN BEGIN
        //            IF GSTComponent."Report View" = GSTComponent."Report View"::CGST THEN
        //               "CGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
        //            ELSE IF GSTComponent."Report View" = GSTComponent."Report View"::"SGST / UTGST" THEN
        //               "SGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
        //            ELSE IF GSTComponent."Report View" = GSTComponent."Report View"::IGST THEN
        //               "IGST%" := FORMAT(DtldGSTLedgEntry3."GST %")
        //            ELSE IF GSTComponent."Report View" = GSTComponent."Report View"::CESS THEN
        //               "CESS%" := FORMAT(DtldGSTLedgEntry3."GST %");
        //               "GST%" += DtldGSTLedgEntry3."GST %";
        //         END;
        //      UNTIL DtldGSTLedgEntry3.NEXT = 0;
        //
        //      WriteToGlbTextVar('IGST_RATE',"IGST%",1,TRUE);
        //      WriteToGlbTextVar('SGST_RATE',"SGST%",1,TRUE);
        //      WriteToGlbTextVar('CGST_RATE',"CGST%",1,TRUE);
        //      WriteToGlbTextVar('CESS_RATE',"CESS%",1,TRUE);
        //      WriteToGlbTextVar('CESS_NONADVOL',FORMAT(ABS(0),0,2),1,TRUE);
        //
        //      Item.GET(DtldGSTLedgEntry2."No.");
        //      UnitofMeasure.GET(DtldGSTLedgEntry2.UOM);
        //      WriteToGlbTextVar('ITEM_NAME',Item.Description,0,TRUE);
        //
        //      WriteToGlbTextVar('HSN_CODE',DtldGSTLedgEntry2."HSN/SAC Code",0,TRUE);
        //
        //      WriteToGlbTextVar('UOM',UnitofMeasure."GST Reporting UQC",0,TRUE);
        //
        //      WriteToGlbTextVar('QUANTITY',FORMAT(ABS(DtldGSTLedgEntry2.Quantity),0,2),1,TRUE);
        //
        //      WriteToGlbTextVar('TAXABLE_VALUE',FORMAT(ABS((DtldGSTLedgEntry2."GST Base Amount")),0,2),1,FALSE);
        //
        //      IF LineCnt <> TotalLines THEN
        //         GlbTextVar += '},'
        //      ELSE
        //         GlbTextVar += '}'
        //   END;
        // UNTIL TaxProEInvoicingBuffer.NEXT = 0;
        TransferShipmentLine.SETRANGE("Document No.", DocNo);
        IF TransferShipmentLine.FINDSET THEN BEGIN
            TotalLines := TransferShipmentLine.COUNT;
            REPEAT
                LineCnt += 1;
                Item.GET(TransferShipmentLine."Item No.");
                UnitofMeasure.GET(TransferShipmentLine."Unit of Measure Code");
                GlbTextVar += '{';
                WriteToGlbTextVar('ITEM_NAME', Item.Description, 0, TRUE);
                WriteToGlbTextVar('HSN_CODE', TransferShipmentLine."HSN/SAC Code", 0, TRUE);
                WriteToGlbTextVar('UOM', UnitofMeasure."UOM For E Invoicing", 0, TRUE); // 15800 "GST Reporting UQC"
                WriteToGlbTextVar('QUANTITY', FORMAT(ABS(TransferShipmentLine.Quantity), 0, 2), 1, TRUE);
                WriteToGlbTextVar('IGST_RATE', "IGST%", 1, TRUE);
                WriteToGlbTextVar('SGST_RATE', "SGST%", 1, TRUE);
                WriteToGlbTextVar('CGST_RATE', "CGST%", 1, TRUE);
                WriteToGlbTextVar('CESS_RATE', "CESS%", 1, TRUE);

                //   WriteToGlbTextVar('TAXABLE_VALUE',FORMAT(ABS((TransferShipmentLine."GST Base Amount")),0,2),1,FALSE); navid

                WriteToGlbTextVar('TAXABLE_VALUE', FORMAT(0), 1, FALSE);
                IF LineCnt <> TotalLines THEN
                    GlbTextVar += '},'
                ELSE
                    GlbTextVar += '}'
            UNTIL TransferShipmentLine.NEXT = 0;
        END;
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

            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
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
        Remarks: Text;
        Status: Text;
        Location: Record 14;
        OriginPinCode: Text;
        ShipPinCode: Text;
        TransShipment: Record 5744;
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
        TransShipment.GET(DocNo);
        TransShipment.TESTFIELD("Distance (Km)", 0);
        /*DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type",DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.",DocNo);
        IF DtldGSTLedgerEntry.FINDFIRST THEN BEGIN*/
        GlbTextVar := '';
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'DISTANCE', 0, FALSE);
        GlbTextVar += '}';

        //    Location.GET(DtldGSTLedgerEntry."Location Code");
        Location.GET(TransShipment."Transfer-from Code");
        Location.TESTFIELD("Post Code");

        OriginPinCode := Location."Post Code";
        ShipPinCode := TransShipment."Transfer-to Post Code";

        //   ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
        /*  ROBOSetup.GET(Location."GST Registration No.");
         ROBOSetup.TESTFIELD("Eway Private Key");
         ROBOSetup.TESTFIELD("Eway Private Value");
         ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
         ROBOSetup.TESTFIELD(ROBOSetup.user_name);
         ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
         ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
        ROBOSetup.Get(Location."GST Registration No.");
        ROBOSetup.TestField("E-Invoice User Name");
        ROBOSetup.TestField(Password);
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

        //END;
    end;

    procedure GeneratePARTA(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        DtldGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        TransShipment: Record 5744;
        EWBNo: Text;
        Remarks: Text;
        Status: Text;
        ROBOOutput: Record 50014;
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
        TransShipment.GET(DocNo);
        //TransShipment.SETAUTOCALCFIELDS("EWay Generated","Eway Cancelled");
        //TransShipment.TESTFIELD("EWay Generated",FALSE);
        DtldGSTLedgerEntry.RESET;
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document Type", DocType);
        DtldGSTLedgerEntry.SETRANGE(DtldGSTLedgerEntry."Document No.", DocNo);
        IF DtldGSTLedgerEntry.FINDSET THEN BEGIN
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'SYNCEWAYBILL', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            WriteToGlbTextVar('GENERATOR_GSTIN', DtldGSTLedgerEntry."Location  Reg. No.", 0, TRUE);

            WriteToGlbTextVar('DOC_NO', DtldGSTLedgerEntry."Document No.", 0, TRUE);
            WriteToGlbTextVar('DOC_TYPE', 'Tax Invoice', 0, FALSE);
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';

            /*
                        ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
                        ROBOSetup.TESTFIELD("Eway Private Key");
                        ROBOSetup.TESTFIELD("Eway Private Value");
                        ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                        ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                        ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                        ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
            ROBOSetup.GET(DtldGSTLedgerEntry."Location  Reg. No.");
            ROBOSetup.TestField("E-Invoice User Name");
            ROBOSetup.TestField(Password);
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

            ROBOOutput."Document Type" := ROBOOutput."Document Type"::Invoice;
            ROBOOutput."Document No." := DocNo;
            ROBOOutput."Eway Bill No" := EWBNo;
            ROBOOutput."Eway Generated" := TRUE;
            IF NOT ROBOOutput.INSERT THEN
                ROBOOutput.MODIFY;
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure GeneratePARTAInter(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        TransShipment: Record 5744;
        TrFromLocation: Record 14;
        EWBNo: Text;
        Remarks: Text;
        Status: Text;
        ROBOOutput: Record 50014;
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
        TransShipment.GET(DocNo);
        TrFromLocation.GET(TransShipment."Transfer-from Code");
        GlbTextVar := '';
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'SYNCEWAYBILL', 0, TRUE);
        GlbTextVar += '"data": [';
        GlbTextVar += '{';
        WriteToGlbTextVar('GENERATOR_GSTIN', TrFromLocation."GST Registration No.", 0, TRUE);

        WriteToGlbTextVar('DOC_NO', TransShipment."No.", 0, TRUE);
        //    WriteToGlbTextVar('DOC_TYPE','Tax Invoice',0,FALSE);
        WriteToGlbTextVar('DOC_TYPE', 'Delivery Challan', 0, FALSE); //added LF_NGno
        GlbTextVar += '}';
        GlbTextVar += ']';
        GlbTextVar += '}';

        //ROBOSetup.GET;
        /* ROBOSetup.GET(TrFromLocation."GST Registration No.");//Added LF-ng
        ROBOSetup.TESTFIELD("Eway Private Key");
        ROBOSetup.TESTFIELD("Eway Private Value");
        ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
        ROBOSetup.TESTFIELD(ROBOSetup.user_name);
        ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
        ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
        ROBOSetup.GET(TrFromLocation."GST Registration No.");
        ROBOSetup.TestField("E-Invoice User Name");
        ROBOSetup.TestField(Password);
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
        ROBOOutput.SETRANGE("Document No.", DocNo);
        IF EWBNo <> '' THEN
            IF ROBOOutput.FINDSET THEN BEGIN
                ROBOOutput."Eway Bill No" := EWBNo;
                ROBOOutput."Eway Generated" := TRUE;
                ROBOOutput.MODIFY;
            END;
        MESSAGE(ReturnMsg, Status, Remarks);
    end;

    procedure UPDATEPARTB(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        TransShipment: Record 5744;
        TrFrLocation: Record 14;
        ROBOOutput: Record 50014;
        State: Record State;
        TransportMethod: Record 259;
        Remarks: Text;
        Status: Text;
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
        TransShipment.GET(DocNo);
        TransShipment.TESTFIELD("Vehicle Type");
        TransShipment.TESTFIELD("Vehicle No.");

        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDFIRST THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);
            TrFrLocation.GET(TransShipment."Transfer-from Code");
            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'UPDATEPARTB', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            WriteToGlbTextVar('Generator_Gstin', TrFrLocation."GST Registration No.", 0, TRUE);
            WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);

            TransportMethod.GET(TransShipment."Transport Method");
            WriteToGlbTextVar('TransportMode', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
            WriteToGlbTextVar('VEHICLE_TYPE', FORMAT(TransShipment."Vehicle Type"), 0, TRUE);
            WriteToGlbTextVar('VehicleNo', TransShipment."Vehicle No.", 0, TRUE);
            IF TransportMethod."Transportation Mode" IN [TransportMethod."Transportation Mode"::Air,
                                                TransportMethod."Transportation Mode"::Rail,
                                                TransportMethod."Transportation Mode"::Ship] THEN BEGIN
                WriteToGlbTextVar('TransDocNumber', TransShipment."No.", 0, TRUE);
                WriteToGlbTextVar('TransDocDate', FORMAT(TransShipment."Posting Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
            END;

            State.GET(TrFrLocation."State Code");

            WriteToGlbTextVar('StateName', State.Description, 0, TRUE);
            WriteToGlbTextVar('FromCityPlace', TrFrLocation.City, 0, TRUE);
            WriteToGlbTextVar('Remarks', '', 0, FALSE);
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';

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
                    end;
            end else
                Message('Generation Invoice Detail Failed!!');

            /* ROBOSetup.GET(TrFrLocation."GST Registration No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800
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
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure CancelEwayBill(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        ROBOOutput: Record 50014;
        TransShipment: Record 5744;
        ReasonCode: Record 231;
        TrFrLocation: Record 14;
        Remarks: Text;
        Status: Text;
        EWBCancelDate: Text;
        NoEwayBillErr: Label 'No Eway Bill found against invoice no.%1';
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JResultArray: JsonArray;

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

        TransShipment.GET(DocNo);
        TrFrLocation.GET(TransShipment."Transfer-from Code");

        GlbTextVar := '';
        GlbTextVar += '{';
        WriteToGlbTextVar('action', 'CANCEL', 0, TRUE);
        GlbTextVar += '"data": [';
        GlbTextVar += '{';
        WriteToGlbTextVar('Generator_Gstin', TrFrLocation."GST Registration No.", 0, TRUE);
        WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
        WriteToGlbTextVar('CancelReason', ReasonCode.Description, 0, TRUE);
        WriteToGlbTextVar('cancelRmrk', TransShipment."Eway Cancel Remark", 0, FALSE);
        GlbTextVar += '}';
        GlbTextVar += ']';
        GlbTextVar += '}';
        /* 
                ROBOSetup.GET(TrFrLocation."GST Registration No.");
                ROBOSetup.TESTFIELD("Eway Private Key");
                ROBOSetup.TESTFIELD("Eway Private Value");
                ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
                ROBOSetup.TESTFIELD(ROBOSetup.user_name);
                ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
                ROBOSetup.TESTFIELD(ROBOSetup.Password); */ // 15800 
        ROBOSetup.GET(TrFrLocation."GST Registration No.");
        ROBOSetup.TestField("E-Invoice User Name");
        ROBOSetup.TestField(Password);

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
        ;
        ROBOOutput."Eway Cancel" := TRUE;
        ROBOOutput.MODIFY;
        MESSAGE(ReturnMsg, Status, Remarks);
    end;

    procedure UpdateTransporter(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund; TransporterCode: Code[20])
    var
        ROBOOutput: Record 50014;
        Transporter: Record 23;
        TrShipment: Record 5744;
        TrFrLocation: Record 14;
        Remarks: Text;
        Status: Text;
        ReturnMsg: Label 'Status : %1\ %2';
    begin
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDSET THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);
            Transporter.GET(TransporterCode);
            TrShipment.GET(DocNo);
            TrFrLocation.GET(TrShipment."Transfer-from Code");

            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'UPDATETRANSPORTER', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            WriteToGlbTextVar('Generator_Gstin', TrFrLocation."GST Registration No.", 0, TRUE);
            WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
            WriteToGlbTextVar('Transport_Gstin', Transporter."GST Registration No.", 0, FALSE);
            GlbTextVar += '{';
            GlbTextVar += ']';
            GlbTextVar += '}';

            ROBOSetup.GET(TrFrLocation."GST Registration No.");
            ROBOSetup.TESTFIELD(ROBOSetup.client_id);
            ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
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
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure ExtendValidity(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        ROBOOutput: Record 50014;
        TransShipment: Record 5744;
        TrFrLocation: Record 14;
        State: Record State;
        TransportMethod: Record 259;
        Remarks: Text;
        Status: Text;
        ExtensionReason: Text;
        ValidUpto: Text;
        ReturnMsg: Label 'Status : %1\ %2';
        ExtenResonErr: Label 'Please specify extension reason.';
    begin
        ROBOOutput.RESET;
        ROBOOutput.SETRANGE(ROBOOutput."Document No.", DocNo);
        IF ROBOOutput.FINDSET THEN BEGIN
            IF ROBOOutput."Eway Bill No" = '' THEN
                ERROR(EwayBillNoErr);

            TransShipment.GET(DocNo);
            TrFrLocation.GET(TransShipment."Transfer-from Code");
            State.GET(TrFrLocation."State Code");

            CASE TransShipment."Eway Extension Reason" OF
                TransShipment."Eway Extension Reason"::"Natural Calamity":
                    ExtensionReason := 'Natural Calamity';
                TransShipment."Eway Extension Reason"::"Law and Order Situation":
                    ExtensionReason := 'Law and Order Situation';
                TransShipment."Eway Extension Reason"::Transshipment:
                    ExtensionReason := 'Transshipment';
                TransShipment."Eway Extension Reason"::Accident:
                    ExtensionReason := 'Accident';
                TransShipment."Eway Extension Reason"::Others:
                    ExtensionReason := 'Others';
                TransShipment."Eway Extension Reason"::" ":
                    ERROR(ExtenResonErr);
            END;

            TransportMethod.GET(TransShipment."Transport Method");

            GlbTextVar := '';
            GlbTextVar += '{';
            WriteToGlbTextVar('action', 'EXTENDVALIDITY', 0, TRUE);
            GlbTextVar += '"data": [';
            GlbTextVar += '{';
            WriteToGlbTextVar('Generator_Gstin', TrFrLocation."GST Registration No.", 0, TRUE);
            WriteToGlbTextVar('EwbNo', ROBOOutput."Eway Bill No", 0, TRUE);
            WriteToGlbTextVar('VehicleNo', TransShipment."Vehicle No.", 0, TRUE);
            WriteToGlbTextVar('FromCity', TrFrLocation.City, 0, TRUE);
            WriteToGlbTextVar('FromState', State.Description, 0, TRUE);
            WriteToGlbTextVar('ExtnRsn', ExtensionReason, 0, TRUE);
            WriteToGlbTextVar('ExtnRemarks', '', 0, TRUE);
            WriteToGlbTextVar('TransDocNumber', FORMAT(TransShipment."LR/RR No."), 0, TRUE);
            WriteToGlbTextVar('TransDocDate', FORMAT(TransShipment."LR/RR Date", 0, '<Day,2>-<Month Text,3>-<Year4>'), 0, TRUE);
            WriteToGlbTextVar('TransportMode', FORMAT(TransportMethod."Transportation Mode"), 0, TRUE);
            WriteToGlbTextVar('RemainingDistance', FORMAT(TransShipment."Eway Remaining (Km)"), 0, TRUE);
            WriteToGlbTextVar('TransitType', FORMAT(TransShipment."Eway Extension Transit Type"), 0, TRUE);
            WriteToGlbTextVar('FromPincode', TrFrLocation."Post Code", 0, TRUE);
            WriteToGlbTextVar('AddressLine1', TrFrLocation.Address, 0, TRUE);
            WriteToGlbTextVar('AddressLine2', TrFrLocation."Address 2", 0, TRUE);
            WriteToGlbTextVar('AddressLine3', '', 0, FALSE);
            GlbTextVar += '}';
            GlbTextVar += ']';
            GlbTextVar += '}';

            ROBOSetup.GET(TrFrLocation."GST Registration No.");
            ROBOSetup.TESTFIELD(ROBOSetup.client_id);
            ROBOSetup.TESTFIELD(ROBOSetup.client_secret);
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Gstin);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);

            /*//12887 commneted ASSERTERROR ERROR coming IN cu67 compilation
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
            ROBOOutput."Eway Bill Valid Till" := ValidUpto;
            ROBOOutput.MODIFY;
            MESSAGE(ReturnMsg, Status, Remarks);
        END;
    end;

    procedure DownloadEwayBillPDF(DocNo: Code[20]; DocType: Option " ",Payment,Invoice,"Credit Memo",,,,Refund)
    var
        ROBOOutput: Record 50014;
        TrShipment: Record 5744;
        TrFrLocation: Record 14;
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
            TrShipment.GET(DocNo);
            TrFrLocation.GET(TrShipment."Transfer-from Code");
            ROBOSetup.GET(TrFrLocation."GST Registration No.");
            ROBOSetup.TestField("E-Invoice User Name");
            ROBOSetup.TestField(Password);
            /* ROBOSetup.GET(TrFrLocation."GST Registration No.");
            ROBOSetup.TESTFIELD("Eway Private Key");
            ROBOSetup.TESTFIELD("Eway Private Value");
            ROBOSetup.TESTFIELD(ROBOSetup.IPAddress);
            ROBOSetup.TESTFIELD(ROBOSetup.user_name);
            ROBOSetup.TESTFIELD(ROBOSetup.Password);
            ROBOSetup.TESTFIELD(ROBOSetup."URL E-Way");
            ROBOSetup.TESTFIELD(ROBOSetup."Eway PDF Path");
 */ // 15800
            URLtext := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + TrFrLocation."GST Registration No." + '&EWBNO=' + ROBOOutput."Eway Bill No" + '&action=GETEWAYBILL';
            // URLtext := EInvoiceSetup."E-Way Bill URL" + '?GSTIN=' + '05AAACE1268K1ZR' + '&EWBNO=' + ROBOOutput."Eway Bill No" + '&action=GETEWAYBILL';
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
            END;
        end;
    end;

    local procedure GetTotInvValue(DocNo: Code[20]): Decimal
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

    local procedure GetTotDCValue(DocNo: Code[20]) Amt: Decimal
    var
        TransferShipmentLine: Record 5745;
    begin
        TransferShipmentLine.SETRANGE("Document No.", DocNo);
        IF TransferShipmentLine.FINDSET THEN
            REPEAT
                Amt += TransferShipmentLine.Amount;
            UNTIL TransferShipmentLine.NEXT = 0;
    end;
}
