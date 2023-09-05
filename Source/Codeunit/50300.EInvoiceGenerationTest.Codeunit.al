codeunit 50300 "E-Invoice Generation"
{
    Permissions = TableData 112 = rm,
                  TableData 114 = rm,
                  TableData 5744 = rm;

    var
        OStream: OutStream;
        IStream: InStream;
        Base64QRText: Text;
        MCounter: Integer;
        M: Integer;
        PostUrl: Text;
        HttpWebRequestMgt: Codeunit "Http Web Request Mgt.";
        body: Text;
        TempBlob: Codeunit "Temp Blob";
        Instr: InStream;
        ApiResult: Text;
        APIError: Label 'Error When Contacting API';
        ItemDetails: Text;
        Req: BigText;
        SIHdr: Record "Sales Invoice Header";
        TempLength: Integer;
        TtlLength: Integer;
        Outstr: OutStream;
        TempBlob1: Codeunit "Temp Blob";
        SHdr: Record "Sales Header";
        ValueEntry: Record "Value Entry";
        ItemLedgerEntry: Record "Item Ledger Entry";
        TotalAmtCust: Decimal;
        CustLedEntry: Record "Cust. Ledger Entry";
        DetGSTLedEnt: Record "Detailed GST Ledger Entry";
        Tdsentry: Record "TDS Entry";


    local procedure DelString(StringToChange: Text): Text
    var
        CharToRemove: Char;
        ASCIIVal: Integer;
        i: Integer;
        FinalString: Text;
    begin
        CLEAR(FinalString);
        StringToChange := DELCHR(StringToChange, '=', '\');
        StringToChange := DELCHR(StringToChange, '=', '–');
        StringToChange := DELCHR(StringToChange, '=', '"');
        StringToChange := DELCHR(StringToChange, '=', '^');
        StringToChange := DELCHR(StringToChange, '=', '”');
        StringToChange := DELCHR(StringToChange, '=', '"');
        StringToChange := DELCHR(StringToChange, '=', '’');
        StringToChange := DELCHR(StringToChange, '=', '’');
        FOR i := 1 TO STRLEN(StringToChange) DO BEGIN
            CharToRemove := StringToChange[i];
            ASCIIVal := CharToRemove;
            IF (STRPOS('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890 @%(),-./', FORMAT(StringToChange[i])) > 0) AND (ASCIIVal <> 160) THEN
                FinalString += FORMAT(StringToChange[i])
            ELSE
                FinalString += ' ';
        END;
        EXIT(FinalString);
    end;

    local procedure ReturnStr(Amt: Decimal): Text
    begin
        EXIT(DELCHR(FORMAT(Amt), '=', ','));
    end;

    procedure AuthenticateCredentials(GSTIN: Code[16])
    var
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        OutputMessage: Text;
        ResultMessage: Text;
        Body: Text;
        TokenExp: DateTime;
        GSTRegistrationNos: Record "GST Registration Nos.";
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetUp.Get();
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
        JsonObj.Add('UserName', GSTRegistrationNos."User Name");
        JsonObj.Add('Password', GSTRegistrationNos.Password);
        JsonObj.Add('Gstin', GSTRegistrationNos.Code);
        JsonObj.WriteTo(JsonTxt);
        // Message(JsonTxt); //TEAM 14763
    end;

    internal procedure GenerateInvoiceIRNNumberUpdated(var SalesInvoiceHeader: Record 112)
    var
        JSONManagement: Codeunit "JSON Management";
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        JFinalTokenValue: JsonToken;
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
        TaxTranscValue: Record "Tax Transaction Value";
        TCSSetup: Record "TCS Setup";
        DayCode: Integer;
        AckDateText: Text;
        txtResponse: Text;
        StringToRead: Text;
        CategoryCode: Text[5];
        ReverseCharge: Text[4];
        CompanyInformation: Record "Company Information";
        RecState: Record State;
        RecCustomer: Record Customer;
        BuyerGSTNo: Code[20];
        BuyerState: Record State;
        Location: Record Location;
        LocationState: Record State;
        ShiptoAddress: Record "Ship-to Address";
        ShipState: Record State;
        SalesInvoiceLine: Record "Sales Invoice Line";
        DGLEntry: Record "Detailed GST Ledger Entry";
        CGSTPer: Decimal;
        SGSTPer: Decimal;
        IGSTPer: Decimal;
        TotItemValue: Decimal;
        DetailedGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SIL: Record "Sales Invoice Line";
        DetailedGSTEntry: Record "Detailed GST Ledger Entry";
        CGSTAmt: Decimal;
        SGSTAmt: Decimal;
        IGSTAmt: Decimal;
        IRNBody: Text;
        CompPhoneNo: Text[10];
        LocPhone: Text[10];
        CustPhone: Text[10];
        ShipPhone: Text[10];
        ItemUnitofMeasure: Record "Item Unit of Measure";
        UnitofMeasure: Record "Unit of Measure";
        UOM: Text[8];
        CompEmail: Text[100];
        LocEmail: Text[100];
        CustEmail: Text[100];
        ShipEmail: Text[100];
        AckDt: DateTime;
        TransType: Text[6];
        ExportCategory: Text[5];
        GSTPayment: Text[4];
        TotAmtinForCurr: Text;
        Country: Record "Country/Region";
        CountryCode: Text[4];
        CurrCode: Text[5];
        ExportDetails: Text;
        MessageID: Integer;
        ExportState: Text[50];
        ShipExpState: Code[5];
        ExportPinCode: Code[6];
        ShipExpPinCode: Code[6];
        ShipGSTNo: Text[20];
        ShippingDetails: Text;
        POS: Code[2];
        POSState: Record State;
        ShippingAgent: Record "Shipping Agent";
        ModeOfTransport: Integer;
        ShipmentMethod: Record "Transport Method";
        SILine: Record "Sales Invoice Line";
        SrNo: Integer;
        Service: Text[1];
        TransporterGSTIN: Text[15];
        TransporterName: Text[100];
        TransDocNo: Text[15];
        TransDocDate: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        QRCode: BigText;
        SignedQRText: Text;
        BillAddress2: Text;
        SalesInvoiceHdrExtend: Record "Sales Invoice Header";
        GSTPercen: Decimal;
        CompInfoName: Text;
        CompInfoName2: Text;
        CompInfoAdd: Text;
        CompInfoAdd2: Text;
        BillToName: Text;
        BillToName2: Text;
        CustLedgerEntry: Record "Cust. Ledger Entry";
        TotalInvVal: Decimal;
        BillToAdd: Text;
        BillToAdd2: Text;
        DetailedGSt: Record "Detailed GST Ledger Entry";
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        ShipToName: Text;
        TCSEntry: Record "TCS Entry";
        ShipToName2: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        Itemdesc: Text;
        Itemdesc2: Text;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CurrencyFactor: Decimal;
        GSTBaseAmtL: Decimal;
        DGLEntryLine: Record "Detailed GST Ledger Entry";
        TpApiDisp: Text;
        Ship_GST: Text[20];
        Ship_StateCode: Code[5];
        Ship_Cust: Record Customer;
        Ship_State: Record State;
        Ship_StateC: Code[5];
        InvType: Text[10];
        LineDetailedGSTLedEnt: Record "Detailed GST Ledger Entry";
        TotalLineAmt: Decimal;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        TCAmt: Decimal;
    begin
        EInvoiceSetUp.Get();
        IF SalesInvoiceHeader."Currency Factor" <> 0 THEN
            CurrencyFactor := SalesInvoiceHeader."Currency Factor"
        ELSE
            CurrencyFactor := 1;

        SalesInvoiceHdrExtend.RESET;
        SalesInvoiceHdrExtend.SETRANGE("No.", SalesInvoiceHeader."No.");
        IF SalesInvoiceHdrExtend.FINDFIRST THEN;
        IF SalesInvoiceHdrExtend."IRN No." <> '' THEN
            ERROR('IRN No. is already generated');


        CLEAR(ItemDetails);
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        Clear(TempBlob);
        Clear(TempBlob1);

        TtlLength := 1;
        CompanyInformation.GET;

        DetailedGSTLedgerEntry.RESET;
        DetailedGSTLedgerEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        IF DetailedGSTLedgerEntry.FINDFIRST THEN;

        Location.RESET;
        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;

        RecState.RESET;
        IF RecState.GET(CompanyInformation."State Code") THEN;

        POSState.RESET;
        IF POSState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN
            POS := POSState."State Code (GST Reg. No.)"
        ELSE
            POS := '96';

        RecCustomer.RESET;
        IF RecCustomer.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN;
        BuyerState.RESET;
        IF BuyerState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN;


        BuyerGSTNo := SalesInvoiceHeader."Customer GST Reg. No.";
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Unregistered THEN
            BuyerGSTNo := 'URP';

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Registered THEN
            CategoryCode := 'B2B';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            CategoryCode := 'Exp';

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            ExportCategory := '"DIR"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"Deemed Export" THEN
            ExportCategory := '"DEM"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit" THEN
            ExportCategory := '"SEZ"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development" THEN
            ExportCategory := '"SED"'
        ELSE
            ExportCategory := 'null';

        ShiptoAddress.RESET;
        IF ShiptoAddress.GET(SalesInvoiceHeader."Sell-to Customer No.", SalesInvoiceHeader."Ship-to Code") THEN;
        ShipState.RESET;
        IF ShipState.GET(SalesInvoiceHeader."GST Ship-to State Code") THEN;

        IF ShiptoAddress."GST Registration No." <> '' THEN
            ShipGSTNo := '"' + ShiptoAddress."GST Registration No." + '"'
        ELSE
            ShipGSTNo := 'null';
        IF DetailedGSTLedgerEntry."Reverse Charge" THEN
            ReverseCharge := 'Y'
        ELSE
            ReverseCharge := 'N';

        IF SalesInvoiceHeader."GST Without Payment of Duty" THEN
            GSTPayment := '"Y"'
        ELSE
            GSTPayment := '"N"';


        CompPhoneNo := 'null';
        LocPhone := 'null';
        CustPhone := 'null';
        ShipPhone := 'null';
        CompEmail := 'null';
        LocEmail := Location."E-Mail";
        CustEmail := 'null';

        ShipEmail := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN BEGIN
            CurrCode := '"' + SalesInvoiceHeader."Currency Code" + '"';
            //SalesInvoiceHeader.CALCFIELDS("Amount to Customer");11443
            //TotAmtinForCurr := ReturnStr(SalesInvoiceHeader."Amount to Customer");11443
            CustLedEntry.Reset();
            CustLedEntry.SetRange("Document No.", SalesInvoiceHeader."No.");
            if CustLedEntry.FindFirst() then;
            TotAmtinForCurr := ReturnStr(CustLedEntry.Amount);

            BuyerGSTNo := 'URP';
            ShipGSTNo := 'null';
            Country.RESET;
            IF Country.GET(SalesInvoiceHeader."Bill-to Country/Region Code") THEN
                CountryCode := '"' + Country."Country Code for E-Invoicing" + '"';
        END
        ELSE BEGIN
            TotAmtinForCurr := FORMAT(0);
            GSTPayment := 'null';
            CountryCode := 'null';
            CurrCode := 'null';
        END;

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            ExportDetails := '{"ShippingBillNo": null,' +
            '"ShippingBillDate": null,' +
            '"PortCode": null,' +
            '"ForeignCurrency": ' + CurrCode + ',' +
            '"CountryCode": ' + CountryCode + ',' +
            '"RefundClaim": null,' +
            '"ExportDuty": "0"},'
        ELSE
            ExportDetails := 'null,';

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) THEN BEGIN
            ExportState := '96';
            ExportPinCode := '999999'
        END ELSE BEGIN
            ExportState := '"' + BuyerState."State Code for E-Invoicing" + '"';  //Open for Production
            //ExportState := '"' + '29' + '"';
            ExportPinCode := SalesInvoiceHeader."Bill-to Post Code";
        END;

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Ship-to State Code" = '') THEN BEGIN
            ShipExpState := '96';
            ShipExpPinCode := '999999'
        END ELSE BEGIN
            ShipExpState := ShipState."State Code for E-Invoicing";
            ShipExpPinCode := SalesInvoiceHeader."Ship-to Post Code";
        END;

        //9509 Start 18-11-2021
        CLEAR(Ship_StateCode);
        CLEAR(Ship_StateC);
        Ship_Cust.RESET;
        IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN BEGIN
            Ship_State.RESET;
            IF Ship_Cust.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN
                Ship_StateCode := Ship_Cust."State Code";
            IF Ship_State.GET(Ship_StateCode) THEN
                Ship_StateC := Ship_State."State Code for E-Invoicing";
        END;
        //9509 End 18-11-2021
        //Calculate Transaction Type

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Registered THEN
            TransType := 'B2B';
        IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development"))
          AND (NOT SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWP';
        IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development"))
          AND (SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWOP';
        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (NOT SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWP';
        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWOP';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"Deemed Export" THEN
            TransType := 'DEXP';
        //Calculate Transaction Type

        SIL.RESET;
        SIL.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SIL.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client//Read//Done
        SIL.CalcSums(Amount, "Line Discount Amount");


        clear(CustLedEntry);
        CustLedEntry.SetAutoCalcFields(Amount, "Amount (LCY)");
        CustLedEntry.SetRange("Document No.", SalesInvoiceHeader."No.");
        if CustLedEntry.FindFirst() then;

        Tdsentry.Reset();
        Tdsentry.SetRange("Document No.", SalesInvoiceHeader."No.");
        Tdsentry.CalcSums("Bal. TDS Including SHE CESS");


        SILine.RESET;
        SILine.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SILine.SETRANGE(Type, SILine.Type::"G/L Account");
        SILine.SETRANGE("No.", EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client//Read
        IF SILine.FINDFIRST THEN;

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'CGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        CGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'SGST');
        DetailedGSTEntry.CALCSUMS("GST Amount");
        SGSTAmt := ABS(DetailedGSTEntry."GST Amount");


        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'IGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        IGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        IF GSTBaseAmtL = 0 THEN
            GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        TotalAmtCust := 0;

        TotAmtinForCurr := ReturnStr(CustLedEntry.Amount);

        TotalLineAmt := 0;
        SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesInvoiceLine.FindSet() then
            repeat
                TotalLineAmt += SalesInvoiceLine."Line Amount";
            until SalesInvoiceLine.next = 0;

        //TEAM 14763 AddOn Code
        if CGSTAmt <> SGSTAmt then
            SGSTAmt := CGSTAmt;
        //TEAM 14763 AddOn Code

        TotalAmtCust += ABS(TotalLineAmt) + CGSTAmt + SGSTAmt + IGSTAmt;

        ShippingAgent.RESET;
        IF ShippingAgent.GET(SalesInvoiceHeader."Shipping Agent Code") THEN;

        /*
        IF ShippingAgent."GST Registration No." <> '' THEN
            TransporterGSTIN := '"' + ShippingAgent."GST Registration No." + '"'
        ELSE
            TransporterGSTIN := 'null';
        IF ShippingAgent.Name <> '' THEN
            TransporterName := '"' + ShippingAgent.Name + '"'
        ELSE
            TransporterName := 'null';

        IF SalesInvoiceHeader."LR/RR No." <> '' THEN
            TransDocNo := '"' + SalesInvoiceHeader."LR/RR No." + '"'
        ELSE
            TransDocNo := 'null';
        IF SalesInvoiceHeader."LR/RR Date" <> 0D THEN
            TransDocDate := '"' + FORMAT(SalesInvoiceHeader."LR/RR Date", 0, '<Day,2>/<Month,2>/<Year4>') + '"'
        ELSE
            TransDocDate := 'null';
        IF SalesInvoiceHeader."Vehicle No." <> '' THEN
            VehicleNo := '"' + SalesInvoiceHeader."Vehicle No." + '"'
        ELSE
            VehicleNo := 'null';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::" " THEN
            VehicleType := 'null';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::ODC THEN
            VehicleType := '"O"';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::Regular THEN
            VehicleType := '"R"';
        */

        ShipmentMethod.RESET;
        IF ShipmentMethod.GET(SalesInvoiceHeader."Transport Method") THEN;

        IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Road THEN
            ModeOfTransport := 1
        ELSE
            IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Rail THEN
                ModeOfTransport := 2
            ELSE
                IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Air THEN
                    ModeOfTransport := 3
                ELSE
                    IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Ship THEN
                        ModeOfTransport := 4;

        CompInfoName := CompanyInformation.Name;
        CompInfoName2 := CompanyInformation."Name 2";
        CompInfoAdd := CompanyInformation.Address;

        CompInfoAdd2 := CompanyInformation."Address 2";
        IF CompInfoAdd2 = '' THEN
            CompInfoAdd2 := '   ';


        BillToName := SalesInvoiceHeader."Bill-to Name";
        BillToName2 := SalesInvoiceHeader."Bill-to Name 2";
        BillToAdd := SalesInvoiceHeader."Bill-to Address";
        BillToAdd2 := SalesInvoiceHeader."Bill-to Address 2";
        IF BillToAdd2 = '' THEN
            BillToAdd2 := '   ';

        ShipToName := SalesInvoiceHeader."Ship-to Name";
        ShipToName2 := SalesInvoiceHeader."Ship-to Name 2";
        ShipToAdd := SalesInvoiceHeader."Ship-to Address";
        ShipToAdd2 := SalesInvoiceHeader."Ship-to Address 2";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        LocationName := Location."Name 3";
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';

        CLEAR(Ship_GST);
        IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN
            IF RecCustomer.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN
                Ship_GST := RecCustomer."GST Registration No.";  //Open for production

        IF SalesInvoiceHeader."Ship-to Code" <> '' THEN
            ShippingDetails := '{"GstinNo": ' + ShipGSTNo + ',' +
                '"LegalName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"TrdName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"Address1": "' + DelString(ShipToAdd) + '",' +
                '"Address2": "' + DelString(ShipToAdd2) + '",' +
                '"Location": "' + SalesInvoiceHeader."Ship-to City" + '",' +
                '"Pincode": ' + ShipExpPinCode + ',' +
                '"StateCode": "' + ShipExpState + '"},'
        ELSE
            IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN
                ShippingDetails := '{"GstinNo": "' + Ship_GST + '",' +
                    '"LegalName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                    '"TrdName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                    '"Address1": "' + DelString(ShipToAdd) + '",' +
                    '"Address2": "' + DelString(ShipToAdd2) + '",' +
                    '"Location": "' + SalesInvoiceHeader."Ship-to City" + '",' +
                    '"Pincode": ' + ShipExpPinCode + ',' +
                    '"StateCode": "' + Ship_StateC + '"},'
            ELSE
                ShippingDetails := 'null,';

        TpApiDisp := 'null,';

        IF SalesInvoiceHeader."Invoice Type" = SalesInvoiceHeader."Invoice Type"::"Debit Note" THEN
            InvType := 'DBN';

        IF SalesInvoiceHeader."Invoice Type" <> SalesInvoiceHeader."Invoice Type"::"Debit Note" THEN
            InvType := 'INV';
        CustLedgerEntry.RESET;
        CustLedgerEntry.SETAUTOCALCFIELDS("Original Amt. (LCY)");
        CustLedgerEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        IF CustLedgerEntry.FINDFIRST THEN
            TotalInvVal := CustLedgerEntry."Original Amt. (LCY)";

        DetailedGSt.Reset();
        DetailedGSt.SetRange("Document No.", SalesInvoiceHeader."No.");
        if DetailedGSt.FindFirst() then;

        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice ';//For UAT--Read
        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';//For Produdction--Read

        //ServicePointManager.SecurityProtocol := SecurityProtocolType.SecurityProtocol::Tls12;//For Produdction--Read//
        IRNBody := '{"action": "INVOICE",' +
          '"Version": "1.1",' +
          '"Irn": "",' +
          '"TpApiTranDtls": {' +
            '"RevReverseCharge": "' + ReverseCharge + '",' +
            '"Typ": "' + TransType + '",' +
            '"TaxPayerType": "GST"' +
          // '"EcomGstin": null,' +
          //'"IgstOnIntra": null' +
          '},' +
          '"TpApiDocDtls": {' +
            //'"DocTyp": "INV",'+
            '"DocTyp": "' + InvType + '",' +
            '"DocNo": "' + SalesInvoiceHeader."No." + '",' +
          '"DocDate": "' + FORMAT(SalesInvoiceHeader."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>') + '",' +
          //'"DocDate": "' + FORMAT(TODAY, 0, '<Day,2>/<Month,2>/<Year4>') + '",' +
          '"OrgInvNo": "' + SalesInvoiceHeader."No." + '"' +
          '},' +
          '"TpApiExpDtls":' + ExportDetails +
          '"TpApiSellerDtls": {' +
            '"GstinNo": "' + Location."GST Registration No." + '",' +//Please open when client go for the Produdction--Read
                                                                     //'"GstinNo": "' + '29AAACB0652N000' + '",' +//Comment-when client go for the Produdction--Read   //+DelString(LocationName)+ DelString(LocationName)+
            '"LegalName": "' + DelString(LocationName) + '",' +// LocationName2
            '"TrdName": "' + DelString(LocationName) + '",' +//  LocationName2
            '"Address1": "' + DelString(LocationAdd) + '",' +
            '"Address2": "' + DelString(LocationAdd2) + '",' +//LocationAdd2
            '"Location": "' + Location.City + '",' +
            '"Pincode": "' + Location."Post Code" + '",' +//Please open when client go for the Produdction--Read
            '"StateCode": "' + LocationState."State Code for E-Invoicing" + '",' +//Please open when client go for the Produdction--Read
                                                                                  //'"Pincode": "560063",' +//Comment-when client go for the Produdction--Read
                                                                                  //'"StateCode": "29",' +//Comment-when client go for the Produdction--Read    //DelString(BillToName2)+ DelString(BillToName2)+
            '"MobileNo": ' + LocPhone + ',' +
            '"EmailId": "' + (LocEmail) + '"' +
          '},' +
          '"TpApiBuyerDtls": {' +
            '"GstinNo": "' + DelString(BuyerGSTNo) + '",' +
            //'"GstinNo": "' + BuyerGSTNo + '",' +
            '"LegalName": "' + DelString(BillToName) + '",' +
            '"TrdName": "' + DelString(BillToName) + '",' +
            '"PlaceOfSupply": "' + POS + '",' +
            '"Address1": "' + DelString(BillToAdd) + '",' +
            '"Address2": "' + DelString(BillToAdd2) + '",' +
            '"Location": "' + SalesInvoiceHeader."Bill-to City" + '",' +
            '"Pincode": ' + ExportPinCode + ',' +
            '"StateCode": ' + ExportState + ',' +
            '"MobileNo": ' + CustPhone + ',' +
            '"EmailId": ' + CustEmail +
          '},' +
            //  '"TpApiDispDtls": {'+
            //    '"CompName": "'+DelString(LocationName2)+'",'+
            //    '"Address1": "'+DelString(LocationAdd)+'",'+
            //    '"Address2": "'+DelString(LocationAdd2)+'",'+
            //    '"Location": "'+Location.City+'",'+
            //    '"Pincode": '+Location."Post Code"+','+
            //    '"StateCode": "'+LocationState."State Code for E-Invoicing"+'"'+
            '"TpApiDispDtls":' + TpApiDisp +
          // '},'+
          '"TpApiShipDtls":' + ShippingDetails +

          '"TpApiValDtls": {' +
            '"TotalTaxableVal": ' + ReturnStr(ROUND(GSTBaseAmtL, 0.01, '=')) + ',' +
            '"TotalSgstVal": ' + ReturnStr(ROUND(SGSTAmt, 0.01, '=')) + ',' +
            '"TotalCgstVal": ' + ReturnStr(ROUND(CGSTAmt, 0.01, '=')) + ',' +
            '"TotalIgstVal": ' + ReturnStr(ROUND(IGSTAmt, 0.01, '=')) + ',' +
            '"TotalCesVal": 0,' +
            '"TotalStateCesVal": 0,' +
            '"Discount": ' + FORMAT(ABS(GetFreight(DetailedGSt."Document No.", DetailedGSt."No.", 2))) + ',' +//7739//1112
            '"TotInvoiceVal": ' + ReturnStr(ROUND(ABS(TotalInvVal) / CurrencyFactor, 0.01, '=')) + ',' +//7739
                                                                                                        //'"TotInvoiceVal": ' + ReturnStr(ABS(CustLedEntry.Amount) - (SGSTAmt + CGSTAmt + IGSTAmt)) + ',' +
            '"RoundOfAmt": ' + ReturnStr(ROUND(SILine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
            // '"TotalInvValueFc": ' + ReturnStr(ROUND(ABS(TotalInvVal), 0.01, '=')) + ',' +

            //'"OthCharge": ' + ReturnStr(ROUND(0 + Tdsentry."Bal. TDS Including SHE CESS", 0.01, '=')) +//7739  //SIL."Charges To Customer" 11443
            //'"OthCharge": ' + ReturnStr(ROUND(0 + 0, 0.01, '=')) +//7739
            '"OthCharge": ' + FORMAT(GetTCSPayableGLAmt(DetailedGSt."Document No.", 2)) +//7739
          '},' +
          '"TpApiItemList": [';

        Req.ADDTEXT(IRNBody, TtlLength);
        TempLength := STRLEN(IRNBody);
        TtlLength += TempLength + 1;

        CLEAR(SrNo);
        CLEAR(Service);

        SalesInvoiceLine.RESET;
        SalesInvoiceLine.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SalesInvoiceLine.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change GL account for the rounding according to client--Read//Done
        SalesInvoiceLine.SETFILTER(Quantity, '<>%1', 0);
        IF SalesInvoiceLine.FINDSET THEN
            REPEAT
                CLEAR(GSTPercen);
                CLEAR(CGSTPer);
                CLEAR(SGSTPer);
                CLEAR(IGSTPer);
                CLEAR(Itemdesc);
                CLEAR(Itemdesc2);

                Itemdesc := SalesInvoiceLine.Description;
                Itemdesc2 := SalesInvoiceLine."Description 2";


                DetGSTLedEnt.Reset();
                DetGSTLedEnt.SetRange("Document No.", SalesInvoiceLine."Document No.");
                DetGSTLedEnt.SetRange("Document Line No.", SalesInvoiceLine."Line No.");
                DetGSTLedEnt.SetFilter("No.", '<>%1', '3604000');
                DetGSTLedEnt.SetFilter("GST Component Code", '%1|%2', 'CGST', 'IGST');
                DetGSTLedEnt.CalcSums("GST Amount", "GST Base Amount");

                Clear(TCAmt);
                TCSSetup.Get();
                TaxTranscValue.Reset();
                TaxTranscValue.SetRange("Tax Record ID", SalesInvoiceLine.RecordId);
                TaxTranscValue.SetRange("Line No. Filter", SalesInvoiceLine."Line No.");
                TaxTranscValue.SetRange("Tax Type", TCSSetup."Tax Type");
                TaxTranscValue.SetRange("Value Type", TaxTranscValue."Value Type"::COMPONENT);
                TaxTranscValue.SetRange("Value ID", 6);
                if TaxTranscValue.FindFirst() then
                    TCAmt := TaxTranscValue.Amount;



                /* TCSEntry.Reset();
                TCSEntry.SetRange("Document No.", SalesInvoiceLine."Document No.");
                if TCSEntry.FindSet() then
                    repeat
                        TCAmt += TCSEntry."TCS Amount";
                    until TCSEntry.Next() = 0;
 */
                DGLEntry.RESET;
                DGLEntry.SETCURRENTKEY("Document No.", "Document Line No.");
                DGLEntry.SETRANGE("Document No.", SalesInvoiceLine."Document No.");
                DGLEntry.SETRANGE("Document Line No.", SalesInvoiceLine."Line No.");
                //DGLEntry.SETRANGE("No.", SalesInvoiceLine."No."); //TEAM 14763 
                IF DGLEntry.FINDSET THEN
                    REPEAT
                        IF DGLEntry."GST Component Code" = 'CGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                CGSTPer := 0.01;
                            END ELSE BEGIN
                                CGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'SGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                SGSTPer := 0.01;
                            END ELSE BEGIN
                                SGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'IGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                IGSTPer := 0.01;
                            END ELSE BEGIN
                                IGSTPer := ABS(DGLEntry."GST Amount");
                                GSTPercen := DGLEntry."GST %";
                            END;
                        END;
                    UNTIL DGLEntry.NEXT = 0;

                //TEAM 14763 AddOn Code

                if (CGSTPer > 0) and (SGSTPer = 0) then
                    GSTPercen += GSTPercen;

                if CGSTPer <> SGSTPer then
                    SGSTPer := CGSTPer;

                //TEAM 14763 AddOn Code


                UnitofMeasure.RESET;
                UnitofMeasure.SETRANGE(Code, SalesInvoiceLine."Unit of Measure Code");
                IF UnitofMeasure.FINDFIRST THEN
                    UOM := '"' + UnitofMeasure."UOM For E Invoicing" + '"'
                ELSE
                    UOM := 'null';

                SrNo += 1;

                // 11889 :: Service Boolean based on Item Category
                IF SalesInvoiceLine."GST Group Type" = SalesInvoiceLine."GST Group Type"::Service THEN
                    Service := 'Y'
                ELSE
                    Service := 'N';

                TotalAmtCust := 0;

                DGLEntryLine.Reset();
                DGLEntryLine.SetRange("Document No.", SalesInvoiceLine."Document No.");
                DGLEntryLine.SetRange("Document Line No.", SalesInvoiceLine."Line No.");
                if DGLEntryLine.FindFirst() then;

                IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development")) THEN
                    TotalAmtCust := (SalesInvoiceLine.Amount / CurrencyFactor - Tdsentry."Bal. TDS Including SHE CESS") + CGSTPer + SGSTPer + IGSTPer
                ELSE
                    TotalAmtCust := (SalesInvoiceLine.Amount / CurrencyFactor - Tdsentry."Bal. TDS Including SHE CESS") + CGSTPer + SGSTPer + IGSTPer; //SalesInvoiceLine."Bal. TDS/TCS Including SHECESS" 11443

                ValueEntry.RESET;
                ValueEntry.SETRANGE("Document Type", ValueEntry."Document Type"::"Sales Invoice");
                ValueEntry.SETRANGE("Document No.", SalesInvoiceLine."Document No.");
                ValueEntry.SETRANGE("Document Line No.", SalesInvoiceLine."Line No.");
                IF ValueEntry.FINDFIRST THEN BEGIN
                    ItemLedgerEntry.GET(ValueEntry."Item Ledger Entry No.");
                END;

                IF ItemDetails = '' THEN BEGIN
                    ItemDetails := '{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesInvoiceLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesInvoiceLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                           '"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine."Line Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      // '"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine.Quantity * SalesInvoiceLine."Unit Price") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Discount Amount" + GetStrucDisc(DGLEntryLine."Document No.", DGLEntryLine."No.", 2, DGLEntryLine."Document Line No.") / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(abs(TCAmt) / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"OtherCharges": '+ReturnStr(ROUND(SalesInvoiceLine."Charges To Customer"/CurrencyFactor+SalesInvoiceLine."Bal. TDS/TCS Including SHECESS",0.01,'='))+','+
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(abs(abs(DetGSTLedEnt."GST Base Amount") + SGSTPer + CGSTPer + IGSTPer + TCAmt))) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}'
                END ELSE BEGIN
                    ItemDetails := ',{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesInvoiceLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesInvoiceLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"TotAmount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                     //'"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine.Quantity * SalesInvoiceLine."Unit Price") / CurrencyFactor, 0.01, '=')) + ',' +
                     '"Discount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Discount Amount" + GetStrucDisc(DGLEntryLine."Document No.", DGLEntryLine."No.", 2, DGLEntryLine."Document Line No.") / CurrencyFactor, 0.01, '=')) + ',' +
                      // '"PreTaxableVal": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(abs(TCAmt) / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"OtherCharges": '+ReturnStr(ROUND(SalesInvoiceLine."Charges To Customer"/CurrencyFactor+SalesInvoiceLine."Bal. TDS/TCS Including SHECESS",0.01,'='))+','+
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(abs(abs(DetGSTLedEnt."GST Base Amount") + SGSTPer + CGSTPer + IGSTPer + TCAmt))) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}';
                END;

                Req.ADDTEXT(ItemDetails, TtlLength);
                TempLength := STRLEN(ItemDetails);
                TtlLength += TempLength + 1;
            UNTIL SalesInvoiceLine.NEXT = 0;

        ItemDetails := ']' + '}';
        Req.ADDTEXT(ItemDetails, TtlLength);
        TempLength := STRLEN(ItemDetails);
        TtlLength += TempLength + 1;

        //MESSAGE(IRNBody); //Display IRN

        GSTRegistrationNos.GET(Location."GST Registration No.");

        MESSAGE('%1', Req); //Display JSON Req


        EinvoiceHttpContent.WriteFrom(Format(Req));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    JOutputObject.Get('Irn', JOutputToken);
                    IRNNo := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('SignedQRCode', JOutputToken);
                    QRText := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('AckNo', JOutputToken);
                    AckNo := JOutputToken.AsValue().AsCode();
                end;
        end;

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
                Message('E-Invoice Generated Successfully!!');
            end;
        end else
            Message('E-Invoice Genreration Failed');
    end;


    procedure CreditNoteIRNNumberNew(var SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        JSONManagement: Codeunit "JSON Management";
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        JFinalTokenValue: JsonToken;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        TotalLineAmt: Decimal;
        AckNo: Code[20];
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        AckDateText: Text;
        txtResponse: Text;
        StringToRead: Text;
        CategoryCode: Text[5];
        ReverseCharge: Text[4];
        CompanyInformation: Record "Company Information";
        RecState: Record State;
        RecCustomer: Record Customer;
        BuyerGSTNo: Code[20];
        BuyerState: Record State;
        Location: Record Location;
        LocationState: Record State;
        ShiptoAddress: Record "Ship-to Address";
        ShipState: Record State;
        SalesInvoiceLine: Record "Sales Invoice Line";
        DGLEntry: Record "Detailed GST Ledger Entry";
        CGSTPer: Decimal;
        SGSTPer: Decimal;
        IGSTPer: Decimal;
        TotItemValue: Decimal;
        DetailedGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SIL: Record "Sales Invoice Line";
        DetailedGSTEntry: Record "Detailed GST Ledger Entry";
        CGSTAmt: Decimal;
        SGSTAmt: Decimal;
        IGSTAmt: Decimal;
        IRNBody: Text;
        CompPhoneNo: Text[10];
        LocPhone: Text[10];
        CustPhone: Text[10];
        ShipPhone: Text[10];
        ItemUnitofMeasure: Record "Item Unit of Measure";
        UnitofMeasure: Record "Unit of Measure";
        UOM: Text[5];
        CompEmail: Text[50];
        LocEmail: Text[50];
        CustEmail: Text[50];
        ShipEmail: Text[50];
        AckDt: DateTime;
        TransType: Text[6];
        ExportCategory: Text[5];
        GSTPayment: Text[4];
        TotAmtinForCurr: Text;
        Country: Record "Country/Region";
        CountryCode: Text[4];
        CurrCode: Text[5];
        ExportDetails: Text;
        MessageID: Integer;
        ExportState: Text[50];
        ShipExpState: Code[5];
        ExportPinCode: Code[6];
        ShipExpPinCode: Code[6];
        ShipGSTNo: Text[20];
        ShippingDetails: Text;
        POS: Code[2];
        POSState: Record State;
        ShippingAgent: Record "Shipping Agent";
        ModeOfTransport: Integer;
        ShipmentMethod: Record "Transport Method";
        SILine: Record "Sales Invoice Line";
        SrNo: Integer;
        Service: Text[1];
        TransporterGSTIN: Text[15];
        TransporterName: Text[100];
        TransDocNo: Text[15];
        TransDocDate: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        QRCode: BigText;
        SignedQRText: Text;
        BillAddress2: Text;
        SalesCrMemoHdrExtend: Record "Sales Cr.Memo Header";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        SCMLine: Record "Sales Cr.Memo Line";
        SCML: Record "Sales Cr.Memo Line";
        SalesInvoiceHeader: Record "Sales Invoice Line";
        GSTPercen: Decimal;
        CompInfoName: Text;
        CompInfoName2: Text;
        CompInfoAdd: Text;
        CompInfoAdd2: Text;
        BillToName: Text;
        BillToName2: Text;
        BillToAdd: Text;
        BillToAdd2: Text;
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        ShipToName: Text;
        ShipToName2: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        Itemdesc: Text;
        Itemdesc2: Text;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CurrencyFactor: Decimal;
        GSTBaseAmtL: Decimal;
        TpApiDisp: Text;
        LineDetailedGSTLedEnt: Record "Detailed GST Ledger Entry";
    begin
        EInvoiceSetUp.Get();
        IF SalesCrMemoHeader."Currency Factor" <> 0 THEN
            CurrencyFactor := SalesCrMemoHeader."Currency Factor"
        ELSE
            CurrencyFactor := 1;

        SalesCrMemoHdrExtend.RESET;
        SalesCrMemoHdrExtend.SETRANGE("No.", SalesCrMemoHeader."No.");
        IF SalesCrMemoHdrExtend.FINDFIRST THEN
            IF SalesCrMemoHdrExtend."IRN No." <> '' THEN
                ERROR('IRN is already generated');

        CLEAR(ItemDetails);
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        Clear(TempBlob);
        Clear(TempBlob1);

        TtlLength := 1;
        CompanyInformation.GET;

        DetailedGSTLedgerEntry.RESET;
        DetailedGSTLedgerEntry.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        IF DetailedGSTLedgerEntry.FINDFIRST THEN;

        clear(CustLedEntry);
        CustLedEntry.SetRange("Document No.", SalesCrMemoHeader."No.");
        if CustLedEntry.FindFirst() then;


        Clear(Tdsentry);
        Tdsentry.SetRange("Document No.", SalesCrMemoHeader."No.");
        Tdsentry.CalcSums("Bal. TDS Including SHE CESS");

        Location.RESET;
        IF Location.GET(SalesCrMemoHeader."Location Code") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;

        RecState.RESET;
        IF RecState.GET(CompanyInformation."State Code") THEN;

        POSState.RESET;
        // 11443IF POSState.GET(DetailedGSTLedgerEntry."Buyer/Seller State Code") THEN
        IF POSState.GET(SalesCrMemoHeader."GST Bill-to State Code") THEN
            POS := POSState."State Code (GST Reg. No.)"
        ELSE
            POS := '96';

        RecCustomer.RESET;
        IF RecCustomer.GET(SalesCrMemoHeader."Sell-to Customer No.") THEN;
        BuyerState.RESET;
        IF BuyerState.GET(SalesCrMemoHeader."GST Bill-to State Code") THEN;

        BuyerGSTNo := SalesCrMemoHeader."Customer GST Reg. No.";
        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Unregistered THEN
            BuyerGSTNo := 'URP';


        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Registered THEN
            CategoryCode := 'B2B';
        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export THEN
            CategoryCode := 'Exp';

        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export THEN
            ExportCategory := '"DIR"'
        ELSE
            ExportCategory := 'null';

        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"Deemed Export" THEN
            ExportCategory := '"DEM"'
        ELSE
            ExportCategory := 'null';
        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Unit" THEN
            ExportCategory := '"SEZ"'
        ELSE
            ExportCategory := 'null';
        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Development" THEN
            ExportCategory := '"SED"'
        ELSE
            ExportCategory := 'null';

        ShiptoAddress.RESET;
        IF ShiptoAddress.GET(SalesCrMemoHeader."Sell-to Customer No.", SalesCrMemoHeader."Ship-to Code") THEN;
        ShipState.RESET;
        IF ShipState.GET(SalesCrMemoHeader."GST Ship-to State Code") THEN;

        IF ShiptoAddress."GST Registration No." <> '' THEN
            ShipGSTNo := '"' + ShiptoAddress."GST Registration No." + '"'
        ELSE
            ShipGSTNo := 'null';
        IF DetailedGSTLedgerEntry."Reverse Charge" THEN
            ReverseCharge := 'Y'
        ELSE
            ReverseCharge := 'N';

        IF SalesCrMemoHeader."GST Without Payment of Duty" THEN
            GSTPayment := '"Y"'
        ELSE
            GSTPayment := '"N"';


        CompPhoneNo := 'null';
        LocPhone := 'null';
        CustPhone := 'null';
        ShipPhone := 'null';
        CompEmail := 'null';
        LocEmail := Location."E-Mail";
        CustEmail := 'null';
        ShipEmail := 'null';

        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export THEN BEGIN
            CurrCode := '"' + SalesCrMemoHeader."Currency Code" + '"';
            TotAmtinForCurr := ReturnStr(CustLedEntry.Amount);
            BuyerGSTNo := 'URP';
            ShipGSTNo := 'null';
            Country.RESET;
            IF Country.GET(SalesCrMemoHeader."Bill-to Country/Region Code") THEN
                CountryCode := '"' + Country."Country Code for E-Invoicing" + '"';
        END
        ELSE BEGIN
            TotAmtinForCurr := FORMAT(0);
            GSTPayment := 'null';
            CountryCode := 'null';
            CurrCode := 'null';
        END;

        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export THEN
            ExportDetails := '{"ShippingBillNo": null,' +
            '"ShippingBillDate": null,' +
            '"PortCode": null,' +
            '"ForeignCurrency": ' + CurrCode + ',' +
            '"CountryCode": ' + CountryCode + ',' +
            '"RefundClaim": null,' +
            '"ExportDuty": "0"},'
        ELSE
            ExportDetails := 'null,';

        //IF (SalesInvoiceHeader."GST Customer Type"=SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Bill-to State Code"='') THEN
        IF (SalesCrMemoHeader."GST Customer Type" IN [SalesCrMemoHeader."GST Customer Type"::Export, SalesCrMemoHeader."GST Customer Type"::"SEZ Development", SalesCrMemoHeader."GST Customer Type"::"SEZ Unit"]) THEN //7739
          BEGIN
            //ExportState:='null';
            ExportState := '96';
            ExportPinCode := '999999'
        END ELSE BEGIN
            ExportState := '"' + BuyerState."State Code for E-Invoicing" + '"';
            ExportPinCode := SalesCrMemoHeader."Bill-to Post Code";
        END;

        IF (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export) AND (SalesCrMemoHeader."GST Ship-to State Code" = '') THEN BEGIN
            ShipExpState := '96';
            ShipExpPinCode := '999999'
        END ELSE BEGIN
            ShipExpState := ShipState."State Code for E-Invoicing";
            ShipExpPinCode := SalesCrMemoHeader."Ship-to Post Code";
        END;

        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Registered THEN
            TransType := 'B2B';
        IF ((SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Unit") OR (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Development"))
          AND (NOT SalesCrMemoHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWP';
        IF ((SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Unit") OR (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Development"))
        AND (SalesCrMemoHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWOP';
        IF (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export) AND (NOT SalesCrMemoHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWP';
        IF (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::Export) AND (SalesCrMemoHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWOP';
        IF SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"Deemed Export" THEN
            TransType := 'DEXP';
        //Calculate Transaction Type

        SCML.RESET;
        SCML.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        SCML.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client--Read//Done
        SCML.CALCSUMS("Line Discount Amount");

        SCMLine.RESET;
        SCMLine.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        SCMLine.SETRANGE(Type, SCMLine.Type::"G/L Account");
        SCMLine.SETRANGE("No.", EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client--Read//Done
        IF SCMLine.FINDFIRST THEN;

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'CGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        CGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'SGST');
        DetailedGSTEntry.CALCSUMS("GST Amount");
        SGSTAmt := ABS(DetailedGSTEntry."GST Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'IGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        IGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        IF GSTBaseAmtL = 0 THEN
            GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");


        TotalLineAmt := 0;
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                TotalLineAmt += SalesCrMemoLine."Line Amount";
            until SalesCrMemoLine.next = 0;

        TotalAmtCust := 0;
        IF ((SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Unit") OR (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Development")) THEN
            TotalAmtCust := Abs(TotalLineAmt) + CGSTAmt + SGSTAmt + IGSTAmt
        ELSE
            TotalAmtCust := Abs(TotalLineAmt) + CGSTAmt + SGSTAmt + IGSTAmt;

        ShippingAgent.RESET;
        IF ShippingAgent.GET(SalesCrMemoHeader."Shipping Agent Code") THEN;

        /*IF ShippingAgent."GST Registration No." <> '' THEN
            TransporterGSTIN := '"' + ShippingAgent."GST Registration No." + '"'
        ELSE
            TransporterGSTIN := 'null';
        IF ShippingAgent.Name <> '' THEN
            TransporterName := '"' + ShippingAgent.Name + '"'
        ELSE
            TransporterName := 'null';

        TransDocNo := 'null';

        TransDocDate := 'null';
        IF SalesCrMemoHeader."Vehicle No." <> '' THEN
            VehicleNo := '"' + SalesCrMemoHeader."Vehicle No." + '"'
        ELSE
            VehicleNo := 'null';
        IF SalesCrMemoHeader."Vehicle Type" = SalesCrMemoHeader."Vehicle Type"::" " THEN
            VehicleType := 'null';
        IF SalesCrMemoHeader."Vehicle Type" = SalesCrMemoHeader."Vehicle Type"::ODC THEN
            VehicleType := '"O"';
        IF SalesCrMemoHeader."Vehicle Type" = SalesCrMemoHeader."Vehicle Type"::Regular THEN
            VehicleType := '"R"';*/

        ShipmentMethod.RESET;
        IF ShipmentMethod.GET(SalesCrMemoHeader."Transport Method") THEN;

        IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Road THEN
            ModeOfTransport := 1
        ELSE
            IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Rail THEN
                ModeOfTransport := 2
            ELSE
                IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Air THEN
                    ModeOfTransport := 3
                ELSE
                    IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Ship THEN
                        ModeOfTransport := 4;


        SalesInvoiceHeader.RESET;
        SalesInvoiceHeader.SETRANGE("No.", SalesCrMemoHeader."Applies-to Doc. No.");
        IF SalesInvoiceHeader.FINDFIRST THEN;


        CompInfoName := CompanyInformation.Name;
        CompInfoName2 := CompanyInformation."Name 2";
        CompInfoAdd := CompanyInformation.Address;
        CompInfoAdd2 := CompanyInformation."Address 2";
        IF CompInfoAdd2 = '' THEN
            CompInfoAdd2 := '   ';

        BillToName := SalesCrMemoHeader."Bill-to Name";
        BillToName2 := SalesCrMemoHeader."Bill-to Name 2";
        BillToAdd := SalesCrMemoHeader."Bill-to Address";
        BillToAdd2 := SalesCrMemoHeader."Bill-to Address 2";
        IF BillToAdd2 = '' THEN
            BillToAdd2 := '   ';
        ShipToName := SalesCrMemoHeader."Ship-to Name";
        ShipToName2 := SalesCrMemoHeader."Ship-to Name 2";
        ShipToAdd := SalesCrMemoHeader."Ship-to Address";
        ShipToAdd2 := SalesCrMemoHeader."Ship-to Address 2";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        LocationName := Location."Name 3";
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';

        IF SalesCrMemoHeader."Ship-to Code" <> '' THEN
            ShippingDetails := '{"GstinNo": ' + ShipGSTNo + ',' +
                '"LegalName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"TrdName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"Address1": "' + DelString(ShipToAdd) + '",' +
                '"Address2": "' + DelString(ShipToAdd2) + '",' +
                '"Location": "' + SalesCrMemoHeader."Ship-to City" + '",' +
                '"Pincode": ' + ShipExpPinCode + ',' +
                '"StateCode": "' + ShipExpState + '"},'
        ELSE
            ShippingDetails := 'null,';

        TpApiDisp := 'null,';


        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice';//For UAT--Read
        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';//For Produdction--Read

        //ServicePointManager.SecurityProtocol := SecurityProtocolType.SecurityProtocol::Tls12;//For Produdction--Read
        IRNBody := '{"action": "INVOICE",' +
          '"Version": "1.1",' +
          '"Irn": "",' +
          '"TpApiTranDtls": {' +
            '"RevReverseCharge": "' + ReverseCharge + '",' +
            '"Typ": "' + TransType + '",' +
            '"TaxPayerType": "GST"' +
          //'"EcomGstin": null,' +
          //'"IgstOnIntra": null' +
          '},' +
          '"TpApiDocDtls": {' +
            '"DocTyp": "CRN",' +
            '"DocNo": "' + SalesCrMemoHeader."No." + '",' +
            '"DocDate": "' + FORMAT(SalesCrMemoHeader."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>') + '",' +
            '"OrgInvNo": "' + SalesCrMemoHeader."Applies-to Doc. No." + '"' +
          '},' +
          '"TpApiExpDtls":' + ExportDetails +
          '"TpApiSellerDtls": {' +
            //'"GstinNo": "' + '29AAACB0652N000' + '",' +//Comment-when client go for the Produdction--Read   //DelString(LocationName)+
            '"GstinNo": "' + Location."GST Registration No." + '",' +//Open-when client go for the Produdction--Read   //DelString(LocationName)+
            '"LegalName": "' + DelString(LocationName) + '",' +//LocationName2
            '"TrdName": "' + DelString(LocationName) + '",' +//LocationName2
            '"Address1": "' + DelString(LocationAdd) + '",' +
            '"Address2": "' + DelString(LocationAdd2) + '",' +
            '"Location": "' + Location.City + '",' +
            '"Pincode": "' + Location."Post Code" + '",' +//Open-when client go for the Produdction--Read
            '"StateCode": "' + LocationState."State Code for E-Invoicing" + '",' +//Open-when client go for the Produdction--Read  //DelString(BillToName2)+
                                                                                  //'"Pincode": "560063",' +//Comment-when client go for the Produdction--Read
                                                                                  //'"StateCode": "29",' +//Comment-when client go for the Produdction--Read  //DelString(BillToName2)+   DelString(LocationName)+
            '"MobileNo": ' + LocPhone + ',' +
            '"EmailId": "' + (LocEmail) + '"' +
          '},' +
          '"TpApiBuyerDtls": {' +
            '"GstinNo": "' + BuyerGSTNo + '",' +
            '"LegalName": "' + DelString(BillToName) + '",' +
            '"TrdName": "' + DelString(BillToName) + '",' +
            '"PlaceOfSupply": "' + POS + '",' +
            '"Address1": "' + DelString(BillToAdd) + '",' +
            '"Address2": "' + DelString(BillToAdd2) + '",' +
            '"Location": "' + SalesCrMemoHeader."Bill-to City" + '",' +
            '"Pincode": ' + ExportPinCode + ',' +
            '"StateCode": ' + ExportState + ',' +
            '"MobileNo": ' + CustPhone + ',' +
            '"EmailId": ' + CustEmail +
          '},' +

            '"TpApiDispDtls":' + TpApiDisp +

          '"TpApiShipDtls":' + ShippingDetails +

          '"TpApiValDtls": {' +
            '"TotalTaxableVal": ' + ReturnStr(ROUND(GSTBaseAmtL, 0.01, '=')) + ',' +
            '"TotalSgstVal": ' + ReturnStr(ROUND(SGSTAmt, 0.01, '=')) + ',' +
            '"TotalCgstVal": ' + ReturnStr(ROUND(CGSTAmt, 0.01, '=')) + ',' +
            '"TotalIgstVal": ' + ReturnStr(ROUND(IGSTAmt, 0.01, '=')) + ',' +
            '"TotalCesVal": 0,' +
            '"TotalStateCesVal": 0,' +
            '"TotInvoiceVal": ' + ReturnStr(ROUND(TotalAmtCust / CurrencyFactor, 0.01, '=') + ROUND(SCMLine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +//7739
                                                                                                                                                               //'"TotInvoiceVal": '+ReturnStr(SIL."Amount To Customer"-(SGSTAmt+CGSTAmt+IGSTAmt))+','+
            '"RoundOfAmt": ' + ReturnStr(ROUND(SCMLine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
            '"TotalInvValueFc": ' + ReturnStr(ROUND(TotalAmtCust, 0.01, '=')) + ',' +
            '"Discount": ' + ReturnStr(ROUND(SCML."Line Discount Amount" / CurrencyFactor, 0.01, '=') * 0) + //7739//1112
                                                                                                             //11443'"OthCharge": ' + ReturnStr(ROUND(SCML."Charges To Customer" / CurrencyFactor + SCML."Bal. TDS/TCS Including SHECESS", 0.01, '=')) +//7739
          '},' +
          '"TpApiItemList": [';

        Req.ADDTEXT(IRNBody, TtlLength);
        TempLength := STRLEN(IRNBody);
        TtlLength += TempLength + 1;

        CLEAR(SrNo);
        CLEAR(Service);

        SalesCrMemoLine.RESET;
        SalesCrMemoLine.SETRANGE("Document No.", SalesCrMemoHeader."No.");
        SalesCrMemoLine.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client--Read//Done
        SalesCrMemoLine.SETFILTER(Type, '<>%1', SalesCrMemoLine.Type::" ");
        SalesCrMemoLine.SETFILTER(Quantity, '<>%1', 0);
        IF SalesCrMemoLine.FINDSET THEN
            REPEAT
                CLEAR(GSTPercen);
                CLEAR(CGSTPer);
                CLEAR(SGSTPer);
                CLEAR(IGSTPer);
                CLEAR(Itemdesc);
                CLEAR(Itemdesc2);

                Itemdesc := SalesCrMemoLine.Description;
                Itemdesc2 := SalesCrMemoLine."Description 2";

                clear(DetGSTLedEnt);
                DetGSTLedEnt.SetRange("Document No.", SalesCrMemoLine."Document No.");
                DetGSTLedEnt.SetRange("Document Line No.", SalesCrMemoLine."Line No.");
                DetGSTLedEnt.SetFilter("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");
                DetGSTLedEnt.SetFilter("GST Component Code", '%1|%2', 'CGST', 'IGST');
                DetGSTLedEnt.CalcSums("GST Amount", "GST Base Amount");


                DGLEntry.RESET;
                DGLEntry.SETRANGE("Document No.", SalesCrMemoLine."Document No.");
                DGLEntry.SETRANGE("Document Line No.", SalesCrMemoLine."Line No.");
                //DGLEntry.SETRANGE("No.", SalesCrMemoLine."No."); //TEAM 14763
                IF DGLEntry.FINDSET THEN
                    REPEAT
                        IF DGLEntry."GST Component Code" = 'CGST' THEN BEGIN
                            IF DGLEntry."GST Base Amount" <= 0.04 THEN BEGIN
                                CGSTPer := 0.01;
                            END ELSE BEGIN
                                CGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'SGST' THEN BEGIN
                            IF DGLEntry."GST Base Amount" <= 0.04 THEN BEGIN
                                SGSTPer := 0.01;
                            END ELSE BEGIN
                                SGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'IGST' THEN BEGIN
                            IF DGLEntry."GST Base Amount" <= 0.04 THEN BEGIN
                                IGSTPer := 0.01;
                            END ELSE BEGIN
                                IGSTPer := ABS(DGLEntry."GST Amount");
                                GSTPercen := DGLEntry."GST %";
                            END;
                        END;
                    UNTIL DGLEntry.NEXT = 0;


                UnitofMeasure.RESET;
                UnitofMeasure.SETRANGE(Code, SalesCrMemoLine."Unit of Measure Code");
                IF UnitofMeasure.FINDFIRST THEN
                    UOM := '"' + UnitofMeasure."UOM For E Invoicing" + '"'
                ELSE
                    UOM := 'null';


                SrNo += 1;
                IF SalesCrMemoLine."GST Group Type" = SalesCrMemoLine."GST Group Type"::Service THEN
                    Service := 'Y'
                ELSE
                    Service := 'N';

                TotalAmtCust := 0;
                IF ((SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Unit") OR (SalesCrMemoHeader."GST Customer Type" = SalesCrMemoHeader."GST Customer Type"::"SEZ Development")) THEN
                    TotalAmtCust := (SalesCrMemoLine.Amount / CurrencyFactor) + CGSTPer + SGSTPer + IGSTPer
                ELSE
                    TotalAmtCust := (SalesCrMemoLine.Amount / CurrencyFactor) + CGSTPer + SGSTPer + IGSTPer;

                IF ItemDetails = '' THEN BEGIN
                    ItemDetails := '{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesCrMemoLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesCrMemoLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesCrMemoLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                      //  '"TotAmount": ' + ReturnStr(ROUND(SalesCrMemoLine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"TotAmount": ' + ReturnStr(ROUND((SalesCrMemoLine.Quantity * SalesCrMemoLine."Unit Price") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(ROUND(SalesCrMemoLine."Line Discount Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(DetGSTLedEnt."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(0 / CurrencyFactor, 0.01, '=')) + ',' +  //SalesCrMemoLine."Charges To Customer" 11443
                      '"AssAmount": ' + ReturnStr(ROUND(DetGSTLedEnt."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                       '"TotItemVal": ' + ReturnStr(ROUND(TotalAmtCust - Tdsentry."Bal. TDS Including SHE CESS", 0.01, '=')) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}'
                END ELSE BEGIN
                    ItemDetails := ',{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesCrMemoLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesCrMemoLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesCrMemoLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"TotAmount": ' + ReturnStr(ROUND(DetGSTLedEnt."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(ROUND(SalesCrMemoLine."Line Discount Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(DetGSTLedEnt."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(0 / CurrencyFactor, 0.01, '=')) + ',' +
                    //11443  '"OtherCharges": ' + ReturnStr(ROUND(SalesCrMemoLine."Charges To Customer" / CurrencyFactor, 0.01, '=')) + ',' +
                    // 11443 '"AssAmount": ' + ReturnStr(ROUND(SalesCrMemoLine."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                    '"AssAmount": ' + ReturnStr(ROUND(DetGSTLedEnt."GST Base Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                       '"TotItemVal": ' + ReturnStr(ROUND(TotalAmtCust - Tdsentry."Bal. TDS Including SHE CESS", 0.01, '=')) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}';
                END;
                Req.ADDTEXT(ItemDetails, TtlLength);
                TempLength := STRLEN(ItemDetails);
                TtlLength += TempLength + 1;
            UNTIL SalesCrMemoLine.NEXT = 0;

        ItemDetails := ']' + '}';
        Req.ADDTEXT(ItemDetails, TtlLength);
        TempLength := STRLEN(ItemDetails);
        TtlLength += TempLength + 1;

        GSTRegistrationNos.GET(Location."GST Registration No.");

        MESSAGE('%1', Req);

        EinvoiceHttpContent.WriteFrom(Format(Req));//15800
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    JOutputObject.Get('Irn', JOutputToken);
                    IRNNo := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('SignedQRCode', JOutputToken);
                    QRText := JOutputToken.AsValue().AsText();
                end;
        end;

        Clear(RecRef);
        RecRef.Get(SalesCrMemoHeader.RecordId);
        if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
            if TempBlob.HasValue() then begin
                FldRef := RecRef.Field(SalesCrMemoHeader.FieldNo("QR Code"));
                TempBlob.ToRecordRef(RecRef, SalesCrMemoHeader.FieldNo("QR Code"));
                RecRef.Field(SalesCrMemoHeader.FieldNo("IRN No.")).Value := IRNNo;
                RecRef.Field(SalesCrMemoHeader.FieldNo("Ack Date")).Value := AckDate;
                RecRef.Modify();
                Message('E-Invoice Generated Successfully!!');
            end;
        end else
            Message('E-Invoice Genreration Failed');

    end;


    procedure GenerateTransferShipIRNNumberUpdated(var TransferShipmentHeader: Record 5744)
    var
        JSONManagement: Codeunit "JSON Management";
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        JFinalTokenValue: JsonToken;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        QRText: Text;
        QRGenerator: Codeunit "QR Generator";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        FldRef: FieldRef;
        txtResponse: Text;
        StringToRead: Text;
        CategoryCode: Text[5];
        ReverseCharge: Text[4];
        CompanyInformation: Record 79;
        RecState: Record State;
        RecCustomer: Record 18;
        BuyerGSTNo: Code[20];
        BuyerState: Record State;
        Location: Record 14;
        LocationState: Record State;
        ShiptoAddress: Record 222;
        ShipState: Record State;
        SalesInvoiceLine: Record 113;
        DGLEntry: Record "Detailed GST Ledger Entry";
        CGSTPer: Decimal;
        SGSTPer: Decimal;
        IGSTPer: Decimal;
        TotItemValue: Decimal;
        DetailedGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SIL: Record 113;
        DetailedGSTEntry: Record "Detailed GST Ledger Entry";
        CGSTAmt: Decimal;
        SGSTAmt: Decimal;
        IGSTAmt: Decimal;
        IRNBody: Text;
        CompPhoneNo: Text[10];
        LocPhone: Text[10];
        CustPhone: Text[10];
        ShipPhone: Text[10];
        ItemUnitofMeasure: Record 5404;
        UnitofMeasure: Record 204;
        UOM: Text[5];
        CompEmail: Text[50];
        LocEmail: Text[50];
        CustEmail: Text[50];
        ShipEmail: Text[50];
        AckNo: Code[20];
        AckDt: DateTime;
        TransType: Text[6];
        ExportCategory: Text[5];
        GSTPayment: Text[4];
        TotAmtinForCurr: Text;
        Country: Record 9;
        CountryCode: Text[4];
        CurrCode: Text[5];
        ExportDetails: Text;
        MessageID: Integer;
        ExportState: Text[50];
        ShipExpState: Code[5];
        ExportPinCode: Code[6];
        ShipExpPinCode: Code[6];
        ShipGSTNo: Text[20];
        ShippingDetails: Text;
        POS: Code[2];
        POSState: Record State;
        ShippingAgent: Record 291;
        ModeOfTransport: Integer;
        ShipmentMethod: Record 259;
        SILine: Record 113;
        SrNo: Integer;
        Service: Text[1];
        TransporterGSTIN: Text[15];
        TransporterName: Text[100];
        TransDocNo: Text[15];
        TransDocDate: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        QRCode: BigText;
        SignedQRText: Text;
        BillAddress2: Text;
        SalesInvoiceHdrExtend: Record 112;
        LocationTo: Record 14;
        TransferShipmentLine: Record 5745;
        TransferShipmentLine2: Record 5745;
        TransferShipmentLine3: Record 5745;
        DispAddress2: Text;
        GSTPercent: Decimal;
        CompInfoName: Text;
        CompInfoName2: Text;
        CompInfoAdd: Text;
        CompInfoAdd2: Text;
        BillToName: Text;
        BillToName2: Text;
        BillToAdd: Text;
        BillToAdd2: Text;
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        ShipToName: Text;
        ShipToName2: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        Itemdesc: Text;
        Itemdesc2: Text;
        GSTRegistrationNos: Record "GST Registration Nos.";
        GSTBaseAmtL: Decimal;
        TpApiDisp: Text;
        LineDetailedGSTLedEnt: Record "Detailed GST Ledger Entry";
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        AckDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        AckDateText: Text;
    begin
        EInvoiceSetUp.Get();
        CLEAR(ItemDetails);
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        Clear(TempBlob);
        Clear(TempBlob1);

        TtlLength := 1;
        CompanyInformation.GET;

        IF TransferShipmentHeader."IRN No." <> '' THEN
            ERROR('IRN is already generated');

        DetailedGSTLedgerEntry.RESET;
        DetailedGSTLedgerEntry.SETRANGE("Document No.", TransferShipmentHeader."No.");
        IF DetailedGSTLedgerEntry.FINDFIRST THEN;

        Location.RESET;
        IF Location.GET(TransferShipmentHeader."Transfer-from Code") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;

        RecState.RESET;
        IF RecState.GET(CompanyInformation."State Code") THEN;


        LocationTo.RESET;
        LocationTo.GET(TransferShipmentHeader."Transfer-to Code");

        POSState.RESET;
        //11443IF POSState.GET(DetailedGSTLedgerEntry."Buyer/Seller State Code") THEN
        IF POSState.GET(LocationTo."State Code") THEN
            POS := POSState."State Code (GST Reg. No.)"
        ELSE
            POS := '96';

        BuyerState.RESET;
        IF BuyerState.GET(LocationTo."State Code") THEN;

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Unregistered THEN
            BuyerGSTNo := 'URP';
        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Registered THEN
            BuyerGSTNo := DetailedGSTLedgerEntry."Buyer/Seller Reg. No.";// Open The When GST No. Is Correct
                                                                         // BuyerGSTNo := '07AABCU9603R1ZP';

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Registered THEN
            CategoryCode := 'B2B';
        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Export THEN
            CategoryCode := 'Exp';

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Export THEN
            ExportCategory := '"DIR"'
        ELSE
            ExportCategory := 'null';

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"Deemed Export" THEN
            ExportCategory := '"DEM"'
        ELSE
            ExportCategory := 'null';

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Unit" THEN
            ExportCategory := '"SEZ"'
        ELSE
            ExportCategory := 'null';

        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Development" THEN
            ExportCategory := '"SED"'
        ELSE
            ExportCategory := 'null';

        IF LocationTo."GST Registration No." <> '' THEN
            ShipGSTNo := '"' + LocationTo."GST Registration No." + '"'
        ELSE
            ShipGSTNo := 'null';

        IF DetailedGSTLedgerEntry."Reverse Charge" THEN
            ReverseCharge := 'Y'
        ELSE
            ReverseCharge := 'N';

        IF DetailedGSTEntry."GST Without Payment of Duty" THEN
            GSTPayment := '"Y"'
        ELSE
            GSTPayment := '"N"';


        CompPhoneNo := 'null';
        LocPhone := 'null';
        CustPhone := 'null';
        ShipPhone := CustPhone;
        CompEmail := 'null';
        LocEmail := Location."E-Mail";
        CustEmail := 'null';
        ShipEmail := CustEmail;
        TotAmtinForCurr := FORMAT(0);
        GSTPayment := 'null';
        CountryCode := 'null';
        CurrCode := 'null';
        ExportDetails := 'null,';


        ExportState := '"' + BuyerState."State Code for E-Invoicing" + '"';
        ExportPinCode := LocationTo."Post Code";

        ShipExpState := ShipState."State Code for E-Invoicing";
        ShipExpPinCode := LocationTo."Post Code";

        ShippingDetails := 'null,';


        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Registered THEN
            TransType := 'B2B';
        IF ((DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Unit") OR (DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Development"))
          AND (NOT DetailedGSTLedgerEntry."GST Without Payment of Duty") THEN
            TransType := 'SEZWP';
        IF ((DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Unit") OR (DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"SEZ Development"))
          AND (DetailedGSTLedgerEntry."GST Without Payment of Duty") THEN
            TransType := 'SEZWOP';
        IF (DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Export) AND (NOT DetailedGSTLedgerEntry."GST Without Payment of Duty") THEN
            TransType := 'EXPWP';
        IF (DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::Export) AND (DetailedGSTLedgerEntry."GST Without Payment of Duty") THEN
            TransType := 'EXPWOP';
        IF DetailedGSTLedgerEntry."GST Customer Type" = DetailedGSTLedgerEntry."GST Customer Type"::"Deemed Export" THEN
            TransType := 'DEXP';
        //Calculate Transaction Type


        TransferShipmentLine.RESET;
        TransferShipmentLine.SETRANGE("Document No.", TransferShipmentHeader."No.");
        TransferShipmentLine.SETFILTER("Item No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client--Read
        TransferShipmentLine.SETFILTER(Quantity, '<>%1', 0);
        //11443TransferShipmentLine.CALCSUMS("GST Base Amount", "Total GST Amount", "Charges to Transfer");
        DetGSTLedEnt.Reset();
        DetGSTLedEnt.SetRange("Document No.", TransferShipmentHeader."No.");
        DetGSTLedEnt.SetFilter("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");
        DetGSTLedEnt.CalcSums("GST Amount", "GST Base Amount");

        TransferShipmentLine2.RESET;
        TransferShipmentLine2.SETRANGE("Document No.", TransferShipmentHeader."No.");
        TransferShipmentLine2.SETFILTER(Quantity, '<>%1', 0);
        TransferShipmentLine2.SETFILTER("Item No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client--Read


        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", TransferShipmentHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'CGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        CGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", TransferShipmentHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'SGST');
        DetailedGSTEntry.CALCSUMS("GST Amount");
        SGSTAmt := ABS(DetailedGSTEntry."GST Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", TransferShipmentHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'IGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        IGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        IF GSTBaseAmtL = 0 THEN
            GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        ShippingAgent.RESET;
        IF ShippingAgent.GET(TransferShipmentHeader."Shipping Agent Code") THEN;

        /*IF ShippingAgent."GST Registration No." <> '' THEN
            TransporterGSTIN := '"' + ShippingAgent."GST Registration No." + '"'
        ELSE
            TransporterGSTIN := 'null';
        IF ShippingAgent.Name <> '' THEN
            TransporterName := '"' + ShippingAgent.Name + '"'
        ELSE
            TransporterName := 'null';
        IF TransferShipmentHeader."LR/RR No." <> '' THEN
            TransDocNo := '"' + TransferShipmentHeader."LR/RR No." + '"'
        ELSE
            TransDocNo := 'null';
        IF TransferShipmentHeader."LR/RR Date" <> 0D THEN
            TransDocDate := '"' + FORMAT(TransferShipmentHeader."LR/RR Date", 0, '<Day,2>/<Month,2>/<Year4>') + '"'
        ELSE
            TransDocDate := 'null';
        IF TransferShipmentHeader."Vehicle No." <> '' THEN
            VehicleNo := '"' + TransferShipmentHeader."Vehicle No." + '"'
        ELSE
            VehicleNo := 'null';*/


        IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::" " THEN
            VehicleType := 'null';
        IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::ODC THEN
            VehicleType := '"O"';
        IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::Regular THEN
            VehicleType := '"R"';

        ShipmentMethod.RESET;
        IF ShipmentMethod.GET(TransferShipmentHeader."Transport Method") THEN;

        IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Road THEN
            ModeOfTransport := 1
        ELSE
            IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Rail THEN
                ModeOfTransport := 2
            ELSE
                IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Air THEN
                    ModeOfTransport := 3
                ELSE
                    IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Ship THEN
                        ModeOfTransport := 4
                    ELSE
                        ModeOfTransport := 1;

        CompInfoName := CompanyInformation.Name;
        CompInfoName2 := CompanyInformation."Name 2";
        CompInfoAdd := CompanyInformation.Address;
        IF CompInfoAdd = '' THEN
            CompInfoAdd := '   ';
        CompInfoAdd2 := CompanyInformation."Address 2";
        IF CompInfoAdd2 = '' THEN
            CompInfoAdd2 := '   ';

        BillToName := TransferShipmentHeader."Transfer-to Name";
        BillToName2 := TransferShipmentHeader."Transfer-to Name 2";
        BillToAdd := TransferShipmentHeader."Transfer-to Address";
        BillToAdd2 := TransferShipmentHeader."Transfer-to Address 2";
        IF BillToAdd2 = '' THEN
            BillToAdd2 := '   ';

        LocationName := TransferShipmentHeader."Transfer-from Name 2";
        LocationName2 := TransferShipmentHeader."Transfer-from Name 2";
        LocationAdd := TransferShipmentHeader."Transfer-from Address";
        LocationAdd2 := TransferShipmentHeader."Transfer-from Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';

        TpApiDisp := 'null,';    //tEAM 11443

        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice';//For UAT--Read
        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';//For Produdction--Read


        //ServicePointManager.SecurityProtocol := SecurityProtocolType.SecurityProtocol::Tls12;//For Produdction--Read
        IRNBody := '{"action": "INVOICE",' +
          '"Version": "1.1",' +
          '"Irn": "",' +
          '"TpApiTranDtls": {' +
            '"RevReverseCharge": "' + ReverseCharge + '",' +
            '"Typ": "' + TransType + '",' +
            '"TaxPayerType": "GST",' +
            '"EcomGstin": null,' +
            '"IgstOnIntra": null' +//7739
          '},' +
          '"TpApiDocDtls": {' +
            '"DocTyp": "INV",' +
            '"DocNo": "' + DELCHR(TransferShipmentHeader."No.", '=', '-') + '",' +
            '"DocDate": "' + FORMAT(TransferShipmentHeader."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>') + '"' +
          '},' +
          '"TpApiExpDtls":' + ExportDetails +
          '"TpApiSellerDtls": {' +
            '"GstinNo": "' + Location."GST Registration No." + '",' +//Open-when client go for the Produdction--Read   //+DelString(LocationName)
                                                                     //'"GstinNo": "' + '29AAACB0652N000' + '",' +//Comment-when client go for the Produdction--Read   //+DelString(LocationName)
            '"LegalName": "' + DelString(LocationName) + '",' +
            '"TrdName": "' + DelString(LocationName) + '",' +
            '"Address1": "' + DelString(LocationAdd) + '",' +
            '"Address2": "' + DelString(LocationAdd2) + '",' +
            '"Location": "' + Location.City + '",' +
            '"Pincode": "' + Location."Post Code" + '",' +//Open-when client go for the Produdction--Read
            '"StateCode": "' + LocationState."State Code for E-Invoicing" + '",' +//Open-when client go for the Produdction--Read
                                                                                  //'"Pincode": "560063",' +//Comment-when client go for the Produdction--Read
                                                                                  //'"StateCode": "29",' +//Comment-when client go for the Produdction--Read   //DelString(BillToName2)+  DelString(BillToName2)+
            '"MobileNo": ' + LocPhone + ',' +
            '"EmailId": "' + (LocEmail) + '"' +
          '},' +
          '"TpApiBuyerDtls": {' +
            '"GstinNo": "' + BuyerGSTNo + '",' +
            '"LegalName": "' + DelString(BillToName) + '",' +
            '"TrdName": "' + DelString(BillToName) + '",' +
            '"PlaceOfSupply": "' + POS + '",' +
            '"Address1": "' + DelString(BillToAdd) + '",' +
            '"Address2": "' + DelString(BillToAdd2) + '",' +
            '"Location": "' + TransferShipmentHeader."Transfer-to City" + '",' +
            '"Pincode": ' + ExportPinCode + ',' +
            '"StateCode": ' + ExportState + ',' +
            '"MobileNo": ' + CustPhone + ',' +
            '"EmailId": ' + CustEmail +
          '},' +
          //  '"TpApiDispDtls": {'+
          //    '"CompName": "'+DelString(LocationName2)+'",'+
          //    '"Address1": "'+DelString(LocationAdd)+'",'+
          //    '"Address2": "'+DelString(LocationAdd2)+'",'+
          //    '"Location": "'+TransferShipmentHeader."Transfer-from City"+'",'+
          //    '"Pincode": '+TransferShipmentHeader."Transfer-from Post Code"+','+
          //    '"StateCode": "'+LocationState."State Code for E-Invoicing"+'"'+
          //  '},'+
          '"TpApiDispDtls":' + TpApiDisp +
          '"TpApiShipDtls":' + ShippingDetails +

          '"TpApiValDtls": {' +
            '"TotalTaxableVal": ' + ReturnStr(ROUND(GSTBaseAmtL, 0.01, '=')) + ',' +
            '"TotalSgstVal": ' + ReturnStr(ROUND(SGSTAmt, 0.01, '=')) + ',' +
            '"TotalCgstVal": ' + ReturnStr(ROUND(CGSTAmt, 0.01, '=')) + ',' +
            '"TotalIgstVal": ' + ReturnStr(ROUND(IGSTAmt, 0.01, '=')) + ',' +
            '"TotalCesVal": 0,' +
            '"TotalStateCesVal": 0,' +
            '"TotInvoiceVal": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") + SGSTAmt + CGSTAmt + IGSTAmt + TransferShipmentLine2.Amount, 0.01, '=')) + ',' +//7739
            '"RoundOfAmt": ' + ReturnStr(ROUND(TransferShipmentLine2.Amount, 0.01, '=')) + ',' +
            '"TotalInvValueFc": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Amount") + SGSTAmt + CGSTAmt + IGSTAmt, 0.01, '=')) + ',' +
            '"Discount": ' + ReturnStr(0) + ',' +
            '"OthCharge": ' + ReturnStr(0) +
          '},' +
          '"TpApiItemList": [';

        Req.ADDTEXT(IRNBody, TtlLength);
        TempLength := STRLEN(IRNBody);
        TtlLength += TempLength + 1;

        CLEAR(SrNo);
        CLEAR(Service);

        TransferShipmentLine3.RESET;
        TransferShipmentLine3.SETRANGE("Document No.", TransferShipmentHeader."No.");
        TransferShipmentLine3.SETFILTER("Item No.", '<>%1', EInvoiceSetUp."GL Account Round 1");
        TransferShipmentLine3.SETFILTER(Quantity, '<>%1', 0);
        IF TransferShipmentLine3.FINDSET THEN
            REPEAT
                CLEAR(GSTPercent);
                CLEAR(CGSTPer);
                CLEAR(SGSTPer);
                CLEAR(IGSTPer);
                CLEAR(Itemdesc);
                CLEAR(Itemdesc2);

                Itemdesc := DelString(TransferShipmentLine3.Description);
                Itemdesc2 := DelString(TransferShipmentLine3."Description 2");

                DGLEntry.RESET;
                DGLEntry.SETRANGE("Document No.", TransferShipmentLine3."Document No.");
                DGLEntry.SETRANGE("Document Line No.", TransferShipmentLine3."Line No.");
                //DGLEntry.SETRANGE("No.", TransferShipmentLine3."Item No.");
                IF DGLEntry.FINDSET THEN
                    REPEAT
                        IF DGLEntry."GST Component Code" = 'CGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                CGSTPer := 0.01;
                            END ELSE BEGIN
                                CGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercent += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'SGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                SGSTPer := 0.01;
                            END ELSE BEGIN
                                SGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercent += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'IGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                IGSTPer := 0.01;
                            END ELSE BEGIN
                                IGSTPer := ABS(DGLEntry."GST Amount");
                                GSTPercent := DGLEntry."GST %";
                            END;
                        END;
                    UNTIL DGLEntry.NEXT = 0;

                LineDetailedGSTLedEnt.Reset();
                LineDetailedGSTLedEnt.SetRange("Document No.", TransferShipmentLine3."Document No.");
                LineDetailedGSTLedEnt.SetRange("Document Line No.", TransferShipmentLine3."Line No.");
                LineDetailedGSTLedEnt.SetFilter("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");
                LineDetailedGSTLedEnt.SetFilter("GST Component Code", '%1|%2', 'CGST', 'IGST');
                LineDetailedGSTLedEnt.CalcSums("GST Amount", "GST Base Amount");

                UnitofMeasure.RESET;
                UnitofMeasure.SETRANGE(Code, TransferShipmentLine3."Unit of Measure Code");
                IF UnitofMeasure.FINDFIRST THEN
                    UOM := '"' + UnitofMeasure."UOM For E Invoicing" + '"'
                ELSE
                    UOM := 'null';

                SrNo += 1;
                Service := 'N';


                IF ItemDetails = '' THEN BEGIN
                    ItemDetails := '{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + TransferShipmentLine3."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(TransferShipmentLine3.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(TransferShipmentLine3."Unit Price", 0.01, '=')) + ',' +
                      //'"UnitPrice": '+ReturnStr(ROUND(TransferShipmentLine3.Amount/TransferShipmentLine3.Quantity,0.01,'='))+','+
                      '"TotAmount": ' + ReturnStr(ROUND(TransferShipmentLine3.Amount, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(0) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount"), 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(0) + ',' +
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount"), 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercent, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount") + ABS(LineDetailedGSTLedEnt."GST Amount"), 0.01, '=')) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}'
                END ELSE BEGIN
                    ItemDetails := ',{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + TransferShipmentLine3."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(TransferShipmentLine3.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(TransferShipmentLine3."Unit Price", 0.01, '=')) + ',' +
                      // '"UnitPrice": '+DelString(ReturnStr(ROUND(TransferShipmentLine3.Amount/TransferShipmentLine3.Quantity,0.01,'=')))+','+
                      '"TotAmount": ' + ReturnStr(ROUND(TransferShipmentLine3.Amount, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(0) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount"), 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(0) + ',' +
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount"), 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercent, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(ABS(LineDetailedGSTLedEnt."GST Base Amount") + ABS(LineDetailedGSTLedEnt."GST Amount"), 0.01, '=')) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}';
                END;
                Req.ADDTEXT(ItemDetails, TtlLength);
                TempLength := STRLEN(ItemDetails);
                TtlLength += TempLength + 1;
            UNTIL TransferShipmentLine3.NEXT = 0;

        ItemDetails := ']' + '}';
        Req.ADDTEXT(ItemDetails, TtlLength);
        TempLength := STRLEN(ItemDetails);
        TtlLength += TempLength + 1;

        GSTRegistrationNos.GET(Location."GST Registration No.");

        MESSAGE('%1', Req);

        EinvoiceHttpContent.WriteFrom(Format(Req));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    JOutputObject.Get('Irn', JOutputToken);
                    IRNNo := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('SignedQRCode', JOutputToken);
                    QRText := JOutputToken.AsValue().AsText();
                end;
        end;

        Clear(RecRef);
        RecRef.Get(TransferShipmentHeader.RecordId);
        if QRGenerator.GenerateQRCodeImage(QRText, TempBlob) then begin
            if TempBlob.HasValue() then begin
                FldRef := RecRef.Field(TransferShipmentHeader.FieldNo("E - Invoicing QR Code"));
                TempBlob.ToRecordRef(RecRef, TransferShipmentHeader.FieldNo("E - Invoicing QR Code"));
                RecRef.Field(TransferShipmentHeader.FieldNo("IRN No.")).Value := IRNNo;
                RecRef.Field(TransferShipmentHeader.FieldNo("Ack Date")).Value := AckDate;
                RecRef.Modify();
                Message('E-Invoice Generated Successfully!!');
            end;
        end else
            Message('E-Invoice Genreration Failed');

    end;

    procedure CancelSalesInvHeaderIRNNo(SalesInvoiceHeader: Record "Sales Invoice Header")
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
        JFinalTokenValue: JsonToken;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        Location: Record Location;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CancelObject: JsonObject;
        Bodytxt: Text;
        CancelDateText: Text;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        CancelDateTime: DateTime;
    begin
        EInvoiceSetUp.Get();
        CancelObject.Add('action', 'CANCEL');
        CancelObject.Add('IRNNo', SalesInvoiceHeader."IRN No.");
        CancelObject.Add('CancelReason', (GetCancelReasonSaleInvHeader(SalesInvoiceHeader)));
        CancelObject.Add('CancelRemarks', Format(SalesInvoiceHeader."Cancel Remarks"));
        CancelObject.WriteTo(Bodytxt);
        // 15800 Message(Bodytxt);

        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        if GSTRegistrationNos.GET(Location."GST Registration No.") then;

        EinvoiceHttpContent.WriteFrom(Bodytxt);
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    SalesInvoiceHeader."E-Inv. Cancelled Date" := CancelDateTime;
                    SalesInvoiceHeader."IRN No." := IRNNo;
                    SalesInvoiceHeader.Modify();
                    Message('E-Invoice Cancelled Successfully!!');
                end;
        end else
            Message(GetLastErrorText());
    end;

    procedure CancelSalesCrMemoHeaderIRNNo(SalesCrMemoHeader: Record "Sales Cr.Memo Header")
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
        JFinalTokenValue: JsonToken;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        Location: Record Location;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CancelObject: JsonObject;
        Bodytxt: Text;
        CancelDateText: Text;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        CancelDateTime: DateTime;
    begin
        EInvoiceSetUp.Get();
        CancelObject.Add('action', 'CANCEL');
        CancelObject.Add('IRNNo', SalesCrMemoHeader."IRN No.");
        CancelObject.Add('CancelReason', (GetCancelReasonSalesCrMemoHeader(SalesCrMemoHeader)));
        CancelObject.Add('CancelRemarks', Format(SalesCrMemoHeader."Cancel Remarks"));
        CancelObject.WriteTo(Bodytxt);
        // 15800 Message(Bodytxt);

        IF Location.GET(SalesCrMemoHeader."Location Code") THEN;
        if GSTRegistrationNos.GET(Location."GST Registration No.") then;

        EinvoiceHttpContent.WriteFrom(Bodytxt);
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    SalesCrMemoHeader."E-Inv. Cancelled Date" := CancelDateTime;
                    SalesCrMemoHeader."IRN No." := IRNNo;
                    SalesCrMemoHeader.Modify();
                    Message('E-Invoice Cancelled Successfully!!');
                end;
        end else
            Message(GetLastErrorText());
    end;

    procedure CancelTransShipmentHeaderIRNNo(TransferShipmentHeader: Record "Transfer Shipment Header")
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
        JFinalTokenValue: JsonToken;
        OutputMessage: Text;
        ResultMessage: Text;
        IRNNo: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        Location: Record Location;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CancelObject: JsonObject;
        Bodytxt: Text;
        CancelDateText: Text;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        CancelDateTime: DateTime;
    begin
        EInvoiceSetUp.Get();
        CancelObject.Add('action', 'CANCEL');
        CancelObject.Add('IRNNo', TransferShipmentHeader."IRN No.");
        CancelObject.Add('CancelReason', (GetCancelReasonTrnsShpemntHeader(TransferShipmentHeader)));
        CancelObject.Add('CancelRemarks', Format(TransferShipmentHeader."Cancel Remarks"));
        CancelObject.WriteTo(Bodytxt);
        // 15800 Message(Bodytxt);

        IF Location.GET(TransferShipmentHeader."Transfer-from Code") THEN;
        if GSTRegistrationNos.GET(Location."GST Registration No.") then;

        EinvoiceHttpContent.WriteFrom(Bodytxt);
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    TransferShipmentHeader."E- Inv Cancelled Date" := CancelDateTime;
                    TransferShipmentHeader."IRN No." := IRNNo;
                    TransferShipmentHeader.Modify();
                    Message('E-Invoice Cancelled Successfully!!');
                end;
        end else
            Message(GetLastErrorText());
    end;


    local procedure GetCancelReasonSalesCrMemoHeader(RecSalesCrMemoHeader: Record "Sales Cr.Memo Header"): Integer
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        SalesCrMemoHeader.Reset();
        SalesCrMemoHeader.SetRange("No.", RecSalesCrMemoHeader."No.");
        if SalesCrMemoHeader.FindFirst() then begin
            if SalesCrMemoHeader."Cancel Reason" = SalesCrMemoHeader."Cancel Reason"::" " then
                exit(0);
            if SalesCrMemoHeader."Cancel Reason" = SalesCrMemoHeader."Cancel Reason"::"Data Entry Mistake" then
                exit(1);
            if SalesCrMemoHeader."Cancel Reason" = SalesCrMemoHeader."Cancel Reason"::Duplicate then
                exit(2);
            if SalesCrMemoHeader."Cancel Reason" = SalesCrMemoHeader."Cancel Reason"::"Order Canceled" then
                exit(3);
            if SalesCrMemoHeader."Cancel Reason" = SalesCrMemoHeader."Cancel Reason"::Other then
                exit(4);
        end;
    end;

    local procedure GetCancelReasonTrnsShpemntHeader(RecTransferShipmentHeader: Record "Transfer Shipment Header"): Integer
    var
        TrnsfrShipmentHeader: Record "Transfer Shipment Header";
    begin
        TrnsfrShipmentHeader.Reset();
        TrnsfrShipmentHeader.SetRange("No.", RecTransferShipmentHeader."No.");
        if TrnsfrShipmentHeader.FindFirst() then begin
            if TrnsfrShipmentHeader."Cancel Reason" = TrnsfrShipmentHeader."Cancel Reason"::" " then
                exit(0);
            if TrnsfrShipmentHeader."Cancel Reason" = TrnsfrShipmentHeader."Cancel Reason"::"Data Entry Mistake" then
                exit(1);
            if TrnsfrShipmentHeader."Cancel Reason" = TrnsfrShipmentHeader."Cancel Reason"::Duplicate then
                exit(2);
            if TrnsfrShipmentHeader."Cancel Reason" = TrnsfrShipmentHeader."Cancel Reason"::"Order Canceled" then
                exit(3);
            if TrnsfrShipmentHeader."Cancel Reason" = TrnsfrShipmentHeader."Cancel Reason"::Other then
                exit(4);
        end;

    end;

    local procedure GetCancelReasonSaleInvHeader(RecSalesInvHeader: Record "Sales Invoice Header"): Integer
    var
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        SalesInvHeader.Reset();
        SalesInvHeader.SetRange("No.", RecSalesInvHeader."No.");
        if SalesInvHeader.FindFirst() then begin
            if SalesInvHeader."Cancel Reason" = SalesInvHeader."Cancel Reason"::" " then
                exit(0);
            if SalesInvHeader."Cancel Reason" = SalesInvHeader."Cancel Reason"::"Data Entry Mistake" then
                exit(1);
            if SalesInvHeader."Cancel Reason" = SalesInvHeader."Cancel Reason"::Duplicate then
                exit(2);
            if SalesInvHeader."Cancel Reason" = SalesInvHeader."Cancel Reason"::"Order Canceled" then
                exit(3);
            if SalesInvHeader."Cancel Reason" = SalesInvHeader."Cancel Reason"::Other then
                exit(4);
        end;
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
        PostUrl := EInvoiceSetup."Download E-Way Bill URL" + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        EinvoiceHttpRequest.SetRequestUri(PostUrl);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpRequest.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpRequest.Method := 'GET';
        EinvoiceHttpHeader.Add('accept', 'application/json');
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.TryAddWithoutValidation('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.TryAddWithoutValidation('Gstin', Location."GST Registration No.");
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(Instr);
            FileName := SalesInvoiceHeader."E-Way Bill No." + '.pdf';
            DownloadFromStream(Instr, 'Export', '', 'All Files (*.*)|*.*', FileName);
            //   Hyperlink('C:/Users/15800/Downloads/701303098188.pdf');
        end;
    end;

    procedure DownloadEWayBillCRMemo(VAR SalesInvoiceHeader: Record "Sales Cr.Memo Header")
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
        // PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        PostUrl := EInvoiceSetup."Download E-Way Bill URL" + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        EinvoiceHttpRequest.SetRequestUri(PostUrl);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpRequest.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpRequest.Method := 'GET';
        EinvoiceHttpHeader.Add('accept', 'application/json');
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.TryAddWithoutValidation('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.TryAddWithoutValidation('Gstin', Location."GST Registration No.");
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(Instr);
            FileName := SalesInvoiceHeader."E-Way Bill No." + '.pdf';
            DownloadFromStream(Instr, 'Export', '', 'All Files (*.*)|*.*', FileName);
            //   Hyperlink('C:/Users/15800/Downloads/701303098188.pdf');
        end;
    end;

    procedure DownloadEWayBillTansfer(VAR SalesInvoiceHeader: Record "Transfer Shipment Header")
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
        IF Location.GET(SalesInvoiceHeader."Transfer-from Code") THEN;
        PostUrl := EInvoiceSetup."Download E-Way Bill URL" + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        //  PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/?GSTIN=' + Location."GST Registration No." + '&EWBNO=' + SalesInvoiceHeader."E-Way Bill No." + '&action=GETEWAYBILL';
        EinvoiceHttpRequest.SetRequestUri(PostUrl);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpRequest.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpRequest.Method := 'GET';
        EinvoiceHttpHeader.Add('accept', 'application/json');
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.TryAddWithoutValidation('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.TryAddWithoutValidation('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.TryAddWithoutValidation('Gstin', Location."GST Registration No.");
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(Instr);
            FileName := SalesInvoiceHeader."E-Way Bill No." + '.pdf';
            DownloadFromStream(Instr, 'Export', '', 'All Files (*.*)|*.*', FileName);
            //   Hyperlink('C:/Users/15800/Downloads/701303098188.pdf');
        end;
    end;


    local procedure GetTCSPayableGLAmt(DocNo: Code[20]; DocType: Integer): Decimal;
    var
        SalesInvoiceLine: Record "Sales Invoice Line";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
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

    local procedure GetFreight(DocNo: Code[20]; ItemCode: Code[20]; DocType: Integer) FreightAmt: Decimal
    var
        PstdStrLineDtls: Record "Posted Str Order Line Details";
    begin
        PstdStrLineDtls.SETRANGE("Invoice No.", DocNo);
        //PstdStrLineDtls.SETRANGE(Type,DocType);
        //PstdStrLineDtls.SETRANGE("Item No.",ItemCode);
        PstdStrLineDtls.SETRANGE("Tax/Charge Type", PstdStrLineDtls."Tax/Charge Type"::Charges);
        PstdStrLineDtls.SETRANGE("Tax/Charge Group", 'FREIGHT');
        IF PstdStrLineDtls.FINDSET THEN
            REPEAT
                FreightAmt += PstdStrLineDtls."Amount (LCY)";
            UNTIL PstdStrLineDtls.NEXT = 0;
        EXIT(FreightAmt);
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

    internal procedure TroubleShootGenerateInvoiceIRNNumberUpdated(var SalesInvoiceHeader: Record 112)
    var
        JSONManagement: Codeunit "JSON Management";
        EinvoiceHttpContent: HttpContent;
        EinvoiceHttpHeader: HttpHeaders;
        EinvoiceHttpRequest: HttpRequestMessage;
        EinvoiceHttpClient: HttpClient;
        EinvoiceHttpResponse: HttpResponseMessage;
        JOutputObject: JsonObject;
        JOutputToken: JsonToken;
        JResultToken: JsonToken;
        JResultObject: JsonObject;
        JFinalTokenValue: JsonToken;
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
        DayCode: Integer;
        AckDateText: Text;
        txtResponse: Text;
        StringToRead: Text;
        CategoryCode: Text[5];
        ReverseCharge: Text[4];
        CompanyInformation: Record "Company Information";
        RecState: Record State;
        RecCustomer: Record Customer;
        BuyerGSTNo: Code[20];
        BuyerState: Record State;
        Location: Record Location;
        LocationState: Record State;
        ShiptoAddress: Record "Ship-to Address";
        ShipState: Record State;
        SalesInvoiceLine: Record "Sales Invoice Line";
        DGLEntry: Record "Detailed GST Ledger Entry";
        CGSTPer: Decimal;
        SGSTPer: Decimal;
        IGSTPer: Decimal;
        TotItemValue: Decimal;
        DetailedGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SIL: Record "Sales Invoice Line";
        DetailedGSTEntry: Record "Detailed GST Ledger Entry";
        CGSTAmt: Decimal;
        SGSTAmt: Decimal;
        IGSTAmt: Decimal;
        IRNBody: Text;
        CompPhoneNo: Text[10];
        LocPhone: Text[10];
        CustPhone: Text[10];
        ShipPhone: Text[10];
        ItemUnitofMeasure: Record "Item Unit of Measure";
        UnitofMeasure: Record "Unit of Measure";
        UOM: Text[8];
        CompEmail: Text[100];
        LocEmail: Text[100];
        CustEmail: Text[100];
        ShipEmail: Text[100];
        AckDt: DateTime;
        TransType: Text[6];
        ExportCategory: Text[5];
        GSTPayment: Text[4];
        TotAmtinForCurr: Text;
        Country: Record "Country/Region";
        CountryCode: Text[4];
        CurrCode: Text[5];
        ExportDetails: Text;
        MessageID: Integer;
        ExportState: Text[50];
        ShipExpState: Code[5];
        ExportPinCode: Code[6];
        ShipExpPinCode: Code[6];
        ShipGSTNo: Text[20];
        ShippingDetails: Text;
        POS: Code[2];
        POSState: Record State;
        ShippingAgent: Record "Shipping Agent";
        ModeOfTransport: Integer;
        ShipmentMethod: Record "Transport Method";
        SILine: Record "Sales Invoice Line";
        SrNo: Integer;
        Service: Text[1];
        TransporterGSTIN: Text[15];
        TransporterName: Text[100];
        TransDocNo: Text[15];
        TransDocDate: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        QRCode: BigText;
        SignedQRText: Text;
        BillAddress2: Text;
        SalesInvoiceHdrExtend: Record "Sales Invoice Header";
        GSTPercen: Decimal;
        CompInfoName: Text;
        CompInfoName2: Text;
        CompInfoAdd: Text;
        CompInfoAdd2: Text;
        BillToName: Text;
        BillToName2: Text;
        CustLedgerEntry: Record "Cust. Ledger Entry";
        TotalInvVal: Decimal;
        BillToAdd: Text;
        BillToAdd2: Text;
        DetailedGSt: Record "Detailed GST Ledger Entry";
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        ShipToName: Text;
        TCSEntry: Record "TCS Entry";
        ShipToName2: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        Itemdesc: Text;
        Itemdesc2: Text;
        GSTRegistrationNos: Record "GST Registration Nos.";
        CurrencyFactor: Decimal;
        GSTBaseAmtL: Decimal;
        DGLEntryLine: Record "Detailed GST Ledger Entry";
        TpApiDisp: Text;
        Ship_GST: Text[20];
        Ship_StateCode: Code[5];
        Ship_Cust: Record Customer;
        Ship_State: Record State;
        Ship_StateC: Code[5];
        InvType: Text[10];
        LineDetailedGSTLedEnt: Record "Detailed GST Ledger Entry";
        TotalLineAmt: Decimal;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        TCAmt: Decimal;
        TaxTranscValue: Record "Tax Transaction Value";
        TCSSetup: Record "TCS Setup";
    begin
        EInvoiceSetUp.Get();
        IF SalesInvoiceHeader."Currency Factor" <> 0 THEN
            CurrencyFactor := SalesInvoiceHeader."Currency Factor"
        ELSE
            CurrencyFactor := 1;

        SalesInvoiceHdrExtend.RESET;
        SalesInvoiceHdrExtend.SETRANGE("No.", SalesInvoiceHeader."No.");
        IF SalesInvoiceHdrExtend.FINDFIRST THEN;
        IF SalesInvoiceHdrExtend."IRN No." <> '' THEN
            ERROR('IRN No. is already generated');


        CLEAR(ItemDetails);
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        Clear(TempBlob);
        Clear(TempBlob1);

        TtlLength := 1;
        CompanyInformation.GET;

        DetailedGSTLedgerEntry.RESET;
        DetailedGSTLedgerEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        IF DetailedGSTLedgerEntry.FINDFIRST THEN;

        Location.RESET;
        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;

        RecState.RESET;
        IF RecState.GET(CompanyInformation."State Code") THEN;

        POSState.RESET;
        IF POSState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN
            POS := POSState."State Code (GST Reg. No.)"
        ELSE
            POS := '96';

        RecCustomer.RESET;
        IF RecCustomer.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN;
        BuyerState.RESET;
        IF BuyerState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN;


        BuyerGSTNo := SalesInvoiceHeader."Customer GST Reg. No.";
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Unregistered THEN
            BuyerGSTNo := 'URP';

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Registered THEN
            CategoryCode := 'B2B';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            CategoryCode := 'Exp';

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            ExportCategory := '"DIR"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"Deemed Export" THEN
            ExportCategory := '"DEM"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit" THEN
            ExportCategory := '"SEZ"'
        ELSE
            ExportCategory := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development" THEN
            ExportCategory := '"SED"'
        ELSE
            ExportCategory := 'null';

        ShiptoAddress.RESET;
        IF ShiptoAddress.GET(SalesInvoiceHeader."Sell-to Customer No.", SalesInvoiceHeader."Ship-to Code") THEN;
        ShipState.RESET;
        IF ShipState.GET(SalesInvoiceHeader."GST Ship-to State Code") THEN;

        IF ShiptoAddress."GST Registration No." <> '' THEN
            ShipGSTNo := '"' + ShiptoAddress."GST Registration No." + '"'
        ELSE
            ShipGSTNo := 'null';
        IF DetailedGSTLedgerEntry."Reverse Charge" THEN
            ReverseCharge := 'Y'
        ELSE
            ReverseCharge := 'N';

        IF SalesInvoiceHeader."GST Without Payment of Duty" THEN
            GSTPayment := '"Y"'
        ELSE
            GSTPayment := '"N"';


        CompPhoneNo := 'null';
        LocPhone := 'null';
        CustPhone := 'null';
        ShipPhone := 'null';
        CompEmail := 'null';
        LocEmail := 'null';
        LocEmail := Location."E-Mail";
        CustEmail := 'null';

        ShipEmail := 'null';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN BEGIN
            CurrCode := '"' + SalesInvoiceHeader."Currency Code" + '"';
            //SalesInvoiceHeader.CALCFIELDS("Amount to Customer");11443
            //TotAmtinForCurr := ReturnStr(SalesInvoiceHeader."Amount to Customer");11443
            CustLedEntry.Reset();
            CustLedEntry.SetRange("Document No.", SalesInvoiceHeader."No.");
            if CustLedEntry.FindFirst() then;
            TotAmtinForCurr := ReturnStr(CustLedEntry.Amount);

            BuyerGSTNo := 'URP';
            ShipGSTNo := 'null';
            Country.RESET;
            IF Country.GET(SalesInvoiceHeader."Bill-to Country/Region Code") THEN
                CountryCode := '"' + Country."Country Code for E-Invoicing" + '"';
        END
        ELSE BEGIN
            TotAmtinForCurr := FORMAT(0);
            GSTPayment := 'null';
            CountryCode := 'null';
            CurrCode := 'null';
        END;

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            ExportDetails := '{"ShippingBillNo": null,' +
            '"ShippingBillDate": null,' +
            '"PortCode": null,' +
            '"ForeignCurrency": ' + CurrCode + ',' +
            '"CountryCode": ' + CountryCode + ',' +
            '"RefundClaim": null,' +
            '"ExportDuty": "0"},'
        ELSE
            ExportDetails := 'null,';

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) THEN BEGIN
            ExportState := '96';
            ExportPinCode := '999999'
        END ELSE BEGIN
            ExportState := '"' + BuyerState."State Code for E-Invoicing" + '"';  //Open for Production
            //ExportState := '"' + '29' + '"';
            ExportPinCode := SalesInvoiceHeader."Bill-to Post Code";
        END;

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Ship-to State Code" = '') THEN BEGIN
            ShipExpState := '96';
            ShipExpPinCode := '999999'
        END ELSE BEGIN
            ShipExpState := ShipState."State Code for E-Invoicing";
            ShipExpPinCode := SalesInvoiceHeader."Ship-to Post Code";
        END;

        //9509 Start 18-11-2021
        CLEAR(Ship_StateCode);
        CLEAR(Ship_StateC);
        Ship_Cust.RESET;
        IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN BEGIN
            Ship_State.RESET;
            IF Ship_Cust.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN
                Ship_StateCode := Ship_Cust."State Code";
            IF Ship_State.GET(Ship_StateCode) THEN
                Ship_StateC := Ship_State."State Code for E-Invoicing";
        END;
        //9509 End 18-11-2021
        //Calculate Transaction Type

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Registered THEN
            TransType := 'B2B';
        IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development"))
          AND (NOT SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWP';
        IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development"))
          AND (SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'SEZWOP';
        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (NOT SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWP';
        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Without Payment of Duty") THEN
            TransType := 'EXPWOP';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"Deemed Export" THEN
            TransType := 'DEXP';
        //Calculate Transaction Type

        SIL.RESET;
        SIL.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SIL.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client//Read//Done
        SIL.CalcSums(Amount, "Line Discount Amount");


        clear(CustLedEntry);
        CustLedEntry.SetAutoCalcFields(Amount, "Amount (LCY)");
        CustLedEntry.SetRange("Document No.", SalesInvoiceHeader."No.");
        if CustLedEntry.FindFirst() then;

        Tdsentry.Reset();
        Tdsentry.SetRange("Document No.", SalesInvoiceHeader."No.");
        Tdsentry.CalcSums("Bal. TDS Including SHE CESS");


        SILine.RESET;
        SILine.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SILine.SETRANGE(Type, SILine.Type::"G/L Account");
        SILine.SETRANGE("No.", EInvoiceSetUp."GL Account Round 1");//Please change the rounding GL account no for respective Client//Read
        IF SILine.FINDFIRST THEN;

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'CGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        CGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'SGST');
        DetailedGSTEntry.CALCSUMS("GST Amount");
        SGSTAmt := ABS(DetailedGSTEntry."GST Amount");


        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'IGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        IGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        IF GSTBaseAmtL = 0 THEN
            GSTBaseAmtL := ABS(DetailedGSTEntry."GST Base Amount");

        TotalAmtCust := 0;

        TotAmtinForCurr := ReturnStr(CustLedEntry.Amount);

        TotalLineAmt := 0;
        SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesInvoiceLine.FindSet() then
            repeat
                TotalLineAmt += SalesInvoiceLine."Line Amount";
            until SalesInvoiceLine.next = 0;

        //TEAM 14763 AddOn Code
        if CGSTAmt <> SGSTAmt then
            SGSTAmt := CGSTAmt;
        //TEAM 14763 AddOn Code

        TotalAmtCust += ABS(TotalLineAmt) + CGSTAmt + SGSTAmt + IGSTAmt;

        ShippingAgent.RESET;
        IF ShippingAgent.GET(SalesInvoiceHeader."Shipping Agent Code") THEN;

        /*
        IF ShippingAgent."GST Registration No." <> '' THEN
            TransporterGSTIN := '"' + ShippingAgent."GST Registration No." + '"'
        ELSE
            TransporterGSTIN := 'null';
        IF ShippingAgent.Name <> '' THEN
            TransporterName := '"' + ShippingAgent.Name + '"'
        ELSE
            TransporterName := 'null';

        IF SalesInvoiceHeader."LR/RR No." <> '' THEN
            TransDocNo := '"' + SalesInvoiceHeader."LR/RR No." + '"'
        ELSE
            TransDocNo := 'null';
        IF SalesInvoiceHeader."LR/RR Date" <> 0D THEN
            TransDocDate := '"' + FORMAT(SalesInvoiceHeader."LR/RR Date", 0, '<Day,2>/<Month,2>/<Year4>') + '"'
        ELSE
            TransDocDate := 'null';
        IF SalesInvoiceHeader."Vehicle No." <> '' THEN
            VehicleNo := '"' + SalesInvoiceHeader."Vehicle No." + '"'
        ELSE
            VehicleNo := 'null';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::" " THEN
            VehicleType := 'null';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::ODC THEN
            VehicleType := '"O"';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::Regular THEN
            VehicleType := '"R"';
        */

        ShipmentMethod.RESET;
        IF ShipmentMethod.GET(SalesInvoiceHeader."Transport Method") THEN;

        IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Road THEN
            ModeOfTransport := 1
        ELSE
            IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Rail THEN
                ModeOfTransport := 2
            ELSE
                IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Air THEN
                    ModeOfTransport := 3
                ELSE
                    IF ShipmentMethod."Transportation Mode" = ShipmentMethod."Transportation Mode"::Ship THEN
                        ModeOfTransport := 4;

        CompInfoName := CompanyInformation.Name;
        CompInfoName2 := CompanyInformation."Name 2";
        CompInfoAdd := CompanyInformation.Address;

        CompInfoAdd2 := CompanyInformation."Address 2";
        IF CompInfoAdd2 = '' THEN
            CompInfoAdd2 := '   ';


        BillToName := SalesInvoiceHeader."Bill-to Name";
        BillToName2 := SalesInvoiceHeader."Bill-to Name 2";
        BillToAdd := SalesInvoiceHeader."Bill-to Address";
        BillToAdd2 := SalesInvoiceHeader."Bill-to Address 2";
        IF BillToAdd2 = '' THEN
            BillToAdd2 := '   ';

        ShipToName := SalesInvoiceHeader."Ship-to Name";
        ShipToName2 := SalesInvoiceHeader."Ship-to Name 2";
        ShipToAdd := SalesInvoiceHeader."Ship-to Address";
        ShipToAdd2 := SalesInvoiceHeader."Ship-to Address 2";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        LocationName := Location."Name 3";
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';

        CLEAR(Ship_GST);
        IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN
            IF RecCustomer.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN
                Ship_GST := RecCustomer."GST Registration No.";  //Open for production

        IF SalesInvoiceHeader."Ship-to Code" <> '' THEN
            ShippingDetails := '{"GstinNo": ' + ShipGSTNo + ',' +
                '"LegalName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"TrdName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                '"Address1": "' + DelString(ShipToAdd) + '",' +
                '"Address2": "' + DelString(ShipToAdd2) + '",' +
                '"Location": "' + SalesInvoiceHeader."Ship-to City" + '",' +
                '"Pincode": ' + ShipExpPinCode + ',' +
                '"StateCode": "' + ShipExpState + '"},'
        ELSE
            IF SalesInvoiceHeader."Sell-to Customer No." <> SalesInvoiceHeader."Bill-to Customer No." THEN
                ShippingDetails := '{"GstinNo": "' + Ship_GST + '",' +
                    '"LegalName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                    '"TrdName": "' + DelString(ShipToName) + DelString(ShipToName2) + '",' +
                    '"Address1": "' + DelString(ShipToAdd) + '",' +
                    '"Address2": "' + DelString(ShipToAdd2) + '",' +
                    '"Location": "' + SalesInvoiceHeader."Ship-to City" + '",' +
                    '"Pincode": ' + ShipExpPinCode + ',' +
                    '"StateCode": "' + Ship_StateC + '"},'
            ELSE
                ShippingDetails := 'null,';

        TpApiDisp := 'null,';

        IF SalesInvoiceHeader."Invoice Type" = SalesInvoiceHeader."Invoice Type"::"Debit Note" THEN
            InvType := 'DBN';

        IF SalesInvoiceHeader."Invoice Type" <> SalesInvoiceHeader."Invoice Type"::"Debit Note" THEN
            InvType := 'INV';
        CustLedgerEntry.RESET;
        CustLedgerEntry.SETAUTOCALCFIELDS("Original Amt. (LCY)");
        CustLedgerEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        IF CustLedgerEntry.FINDFIRST THEN
            TotalInvVal := CustLedgerEntry."Original Amt. (LCY)";

        DetailedGSt.Reset();
        DetailedGSt.SetRange("Document No.", SalesInvoiceHeader."No.");
        if DetailedGSt.FindFirst() then;

        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice ';//For UAT--Read
        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';//For Produdction--Read

        //ServicePointManager.SecurityProtocol := SecurityProtocolType.SecurityProtocol::Tls12;//For Produdction--Read//
        IRNBody := '{"action": "INVOICE",' +
          '"Version": "1.1",' +
          '"Irn": "",' +
          '"TpApiTranDtls": {' +
            '"RevReverseCharge": "' + ReverseCharge + '",' +
            '"Typ": "' + TransType + '",' +
            '"TaxPayerType": "GST",' +
          // '"EcomGstin": null,' +
          //'"IgstOnIntra": null' +
          '},' +
          '"TpApiDocDtls": {' +
            //'"DocTyp": "INV",'+
            '"DocTyp": "' + InvType + '",' +
            '"DocNo": "' + SalesInvoiceHeader."No." + '",' +
          '"DocDate": "' + FORMAT(SalesInvoiceHeader."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>') + '",' +
          //'"DocDate": "' + FORMAT(TODAY, 0, '<Day,2>/<Month,2>/<Year4>') + '",' +
          '"OrgInvNo": "' + SalesInvoiceHeader."No." + '"' +
          '},' +
          '"TpApiExpDtls":' + ExportDetails +
          '"TpApiSellerDtls": {' +
            '"GstinNo": "' + Location."GST Registration No." + '",' +//Please open when client go for the Produdction--Read
                                                                     //'"GstinNo": "' + '29AAACB0652N000' + '",' +//Comment-when client go for the Produdction--Read   //+DelString(LocationName)+ DelString(LocationName)+
            '"LegalName": "' + DelString(LocationName) + '",' +// LocationName2
            '"TrdName": "' + DelString(LocationName) + '",' +//  LocationName2
            '"Address1": "' + DelString(LocationAdd) + '",' +
            '"Address2": "' + DelString(LocationAdd2) + '",' +//LocationAdd2
            '"Location": "' + Location.City + '",' +
            '"Pincode": "' + Location."Post Code" + '",' +//Please open when client go for the Produdction--Read
            '"StateCode": "' + LocationState."State Code for E-Invoicing" + '",' +//Please open when client go for the Produdction--Read
                                                                                  //'"Pincode": "560063",' +//Comment-when client go for the Produdction--Read
                                                                                  //'"StateCode": "29",' +//Comment-when client go for the Produdction--Read    //DelString(BillToName2)+ DelString(BillToName2)+
            '"MobileNo": ' + LocPhone + ',' +
            '"EmailId": "' + (LocEmail) + '"' +
          '},' +
          '"TpApiBuyerDtls": {' +
            '"GstinNo": "' + DelString(BuyerGSTNo) + '",' +
            //'"GstinNo": "' + BuyerGSTNo + '",' +
            '"LegalName": "' + DelString(BillToName) + '",' +
            '"TrdName": "' + DelString(BillToName) + '",' +
            '"PlaceOfSupply": "' + POS + '",' +
            '"Address1": "' + DelString(BillToAdd) + '",' +
            '"Address2": "' + DelString(BillToAdd2) + '",' +
            '"Location": "' + SalesInvoiceHeader."Bill-to City" + '",' +
            '"Pincode": ' + ExportPinCode + ',' +
            '"StateCode": ' + ExportState + ',' +
            '"MobileNo": ' + CustPhone + ',' +
            '"EmailId": ' + CustEmail +
          '},' +
            //  '"TpApiDispDtls": {'+
            //    '"CompName": "'+DelString(LocationName2)+'",'+
            //    '"Address1": "'+DelString(LocationAdd)+'",'+
            //    '"Address2": "'+DelString(LocationAdd2)+'",'+
            //    '"Location": "'+Location.City+'",'+
            //    '"Pincode": '+Location."Post Code"+','+
            //    '"StateCode": "'+LocationState."State Code for E-Invoicing"+'"'+
            '"TpApiDispDtls":' + TpApiDisp +
          // '},'+
          '"TpApiShipDtls":' + ShippingDetails +

          '"TpApiValDtls": {' +
            '"TotalTaxableVal": ' + ReturnStr(ROUND(GSTBaseAmtL, 0.01, '=')) + ',' +
            '"TotalSgstVal": ' + ReturnStr(ROUND(SGSTAmt, 0.01, '=')) + ',' +
            '"TotalCgstVal": ' + ReturnStr(ROUND(CGSTAmt, 0.01, '=')) + ',' +
            '"TotalIgstVal": ' + ReturnStr(ROUND(IGSTAmt, 0.01, '=')) + ',' +
            '"TotalCesVal": 0,' +
            '"TotalStateCesVal": 0,' +
             '"Discount": ' + FORMAT(ABS(GetFreight(DetailedGSt."Document No.", DetailedGSt."No.", 2))) + ',' +//7739//1112
            '"TotInvoiceVal": ' + ReturnStr(ROUND(ABS(TotalInvVal) / CurrencyFactor, 0.01, '=')) + ',' +//7739
                                                                                                        //'"TotInvoiceVal": ' + ReturnStr(ABS(CustLedEntry.Amount) - (SGSTAmt + CGSTAmt + IGSTAmt)) + ',' +
            '"RoundOfAmt": ' + ReturnStr(ROUND(SILine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
            //  '"TotalInvValueFc": ' + ReturnStr(ROUND(ABS(TotalInvVal), 0.01, '=')) + ',' +
            '"Discount": ' + FORMAT(ABS(GetFreight(DetailedGSt."Document No.", DetailedGSt."No.", 2))) + ',' +//7739//1112
                                                                                                              //'"OthCharge": ' + ReturnStr(ROUND(0 + Tdsentry."Bal. TDS Including SHE CESS", 0.01, '=')) +//7739  //SIL."Charges To Customer" 11443
                                                                                                              //'"OthCharge": ' + ReturnStr(ROUND(0 + 0, 0.01, '=')) +//7739
            '"OthCharge": ' + FORMAT(GetTCSPayableGLAmt(DetailedGSt."Document No.", 2)) +//7739
          '},' +
          '"TpApiItemList": [';

        Req.ADDTEXT(IRNBody, TtlLength);
        TempLength := STRLEN(IRNBody);
        TtlLength += TempLength + 1;

        CLEAR(SrNo);
        CLEAR(Service);

        SalesInvoiceLine.RESET;
        SalesInvoiceLine.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SalesInvoiceLine.SETFILTER("No.", '<>%1', EInvoiceSetUp."GL Account Round 1");//Please change GL account for the rounding according to client--Read//Done
        SalesInvoiceLine.SETFILTER(Quantity, '<>%1', 0);
        IF SalesInvoiceLine.FINDSET THEN
            REPEAT
                CLEAR(GSTPercen);
                CLEAR(CGSTPer);
                CLEAR(SGSTPer);
                CLEAR(IGSTPer);
                CLEAR(Itemdesc);
                CLEAR(Itemdesc2);

                Itemdesc := SalesInvoiceLine.Description;
                Itemdesc2 := SalesInvoiceLine."Description 2";


                DetGSTLedEnt.Reset();
                DetGSTLedEnt.SetRange("Document No.", SalesInvoiceLine."Document No.");
                DetGSTLedEnt.SetRange("Document Line No.", SalesInvoiceLine."Line No.");
                DetGSTLedEnt.SetFilter("No.", '<>%1', '3604000');
                DetGSTLedEnt.SetFilter("GST Component Code", '%1|%2', 'CGST', 'IGST');
                DetGSTLedEnt.CalcSums("GST Amount", "GST Base Amount");


                Clear(TCAmt);
                TCSSetup.Get();
                TaxTranscValue.Reset();
                TaxTranscValue.SetRange("Tax Record ID", SalesInvoiceLine.RecordId);
                TaxTranscValue.SetRange("Line No. Filter", SalesInvoiceLine."Line No.");
                TaxTranscValue.SetRange("Tax Type", TCSSetup."Tax Type");
                TaxTranscValue.SetRange("Value Type", TaxTranscValue."Value Type"::COMPONENT);
                TaxTranscValue.SetRange("Value ID", 6);
                if TaxTranscValue.FindFirst() then
                    TCAmt := TaxTranscValue.Amount;



                /* Clear(TCAmt);
                TCSEntry.Reset();
                TCSEntry.SetRange("Document No.", SalesInvoiceLine."Document No.");
                if TCSEntry.FindSet() then
                    repeat
                        TCAmt += TCSEntry."TCS Amount";
                    until TCSEntry.Next() = 0;
 */
                DGLEntry.RESET;
                DGLEntry.SETCURRENTKEY("Document No.", "Document Line No.");
                DGLEntry.SETRANGE("Document No.", SalesInvoiceLine."Document No.");
                DGLEntry.SETRANGE("Document Line No.", SalesInvoiceLine."Line No.");
                //DGLEntry.SETRANGE("No.", SalesInvoiceLine."No."); //TEAM 14763 
                IF DGLEntry.FINDSET THEN
                    REPEAT
                        IF DGLEntry."GST Component Code" = 'CGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                CGSTPer := 0.01;
                            END ELSE BEGIN
                                CGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'SGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                SGSTPer := 0.01;
                            END ELSE BEGIN
                                SGSTPer += ABS(DGLEntry."GST Amount");
                                GSTPercen += DGLEntry."GST %";
                            END;
                        END;
                        IF DGLEntry."GST Component Code" = 'IGST' THEN BEGIN
                            IF ABS(DGLEntry."GST Base Amount") <= 0.04 THEN BEGIN
                                IGSTPer := 0.01;
                            END ELSE BEGIN
                                IGSTPer := ABS(DGLEntry."GST Amount");
                                GSTPercen := DGLEntry."GST %";
                            END;
                        END;
                    UNTIL DGLEntry.NEXT = 0;

                //TEAM 14763 AddOn Code

                if (CGSTPer > 0) and (SGSTPer = 0) then
                    GSTPercen += GSTPercen;

                if CGSTPer <> SGSTPer then
                    SGSTPer := CGSTPer;

                //TEAM 14763 AddOn Code


                UnitofMeasure.RESET;
                UnitofMeasure.SETRANGE(Code, SalesInvoiceLine."Unit of Measure Code");
                IF UnitofMeasure.FINDFIRST THEN
                    UOM := '"' + UnitofMeasure."UOM For E Invoicing" + '"'
                ELSE
                    UOM := 'null';

                SrNo += 1;

                // 11889 :: Service Boolean based on Item Category
                IF SalesInvoiceLine."GST Group Type" = SalesInvoiceLine."GST Group Type"::Service THEN
                    Service := 'Y'
                ELSE
                    Service := 'N';

                TotalAmtCust := 0;

                DGLEntryLine.Reset();
                DGLEntryLine.SetRange("Document No.", SalesInvoiceLine."Document No.");
                DGLEntryLine.SetRange("Document Line No.", SalesInvoiceLine."Line No.");
                if DGLEntryLine.FindFirst() then;

                IF ((SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Unit") OR (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::"SEZ Development")) THEN
                    TotalAmtCust := (SalesInvoiceLine.Amount / CurrencyFactor - Tdsentry."Bal. TDS Including SHE CESS") + CGSTPer + SGSTPer + IGSTPer
                ELSE
                    TotalAmtCust := (SalesInvoiceLine.Amount / CurrencyFactor - Tdsentry."Bal. TDS Including SHE CESS") + CGSTPer + SGSTPer + IGSTPer; //SalesInvoiceLine."Bal. TDS/TCS Including SHECESS" 11443

                ValueEntry.RESET;
                ValueEntry.SETRANGE("Document Type", ValueEntry."Document Type"::"Sales Invoice");
                ValueEntry.SETRANGE("Document No.", SalesInvoiceLine."Document No.");
                ValueEntry.SETRANGE("Document Line No.", SalesInvoiceLine."Line No.");
                IF ValueEntry.FINDFIRST THEN BEGIN
                    ItemLedgerEntry.GET(ValueEntry."Item Ledger Entry No.");
                END;

                IF ItemDetails = '' THEN BEGIN
                    ItemDetails := '{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesInvoiceLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesInvoiceLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                    '"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine."Line Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      // '"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine.Quantity * SalesInvoiceLine."Unit Price") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"Discount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Discount Amount" + GetStrucDisc(DGLEntryLine."Document No.", DGLEntryLine."No.", 2, DGLEntryLine."Document Line No.") / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(abs(TCAmt) / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"OtherCharges": '+ReturnStr(ROUND(SalesInvoiceLine."Charges To Customer"/CurrencyFactor+SalesInvoiceLine."Bal. TDS/TCS Including SHECESS",0.01,'='))+','+
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(abs(abs(DetGSTLedEnt."GST Base Amount") + SGSTPer + CGSTPer + IGSTPer + TCAmt))) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}'
                END ELSE BEGIN
                    ItemDetails := ',{' +
                      '"SiNo": "' + FORMAT(SrNo) + '",' +
                      '"ProductDesc": "' + DelString(Itemdesc) + DelString(Itemdesc2) + '",' +
                      '"IsService": "' + Service + '",' +
                      '"HsnCode": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                      '"BarCode": null,' +
                      '"Quantity": ' + ReturnStr(ROUND(SalesInvoiceLine.Quantity, 0.01, '=')) + ',' +
                      '"FreeQuantity": 0,' +
                      '"Unit": ' + UOM + ',' +
                      '"UnitPrice": ' + ReturnStr(ROUND(SalesInvoiceLine."Unit Price" / CurrencyFactor, 0.01, '=')) + ',' +
                      '"TotAmount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Amount" / CurrencyFactor, 0.01, '=')) + ',' +
                     //'"TotAmount": ' + ReturnStr(ROUND((SalesInvoiceLine.Quantity * SalesInvoiceLine."Unit Price") / CurrencyFactor, 0.01, '=')) + ',' +
                     '"Discount": ' + ReturnStr(ROUND(SalesInvoiceLine."Line Discount Amount" + GetStrucDisc(DGLEntryLine."Document No.", DGLEntryLine."No.", 2, DGLEntryLine."Document Line No.") / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"PreTaxableVal": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"OtherCharges": ' + ReturnStr(ROUND(abs(TCAmt) / CurrencyFactor, 0.01, '=')) + ',' +
                      //'"OtherCharges": '+ReturnStr(ROUND(SalesInvoiceLine."Charges To Customer"/CurrencyFactor+SalesInvoiceLine."Bal. TDS/TCS Including SHECESS",0.01,'='))+','+
                      '"AssAmount": ' + ReturnStr(ROUND(ABS(DetGSTLedEnt."GST Base Amount") / CurrencyFactor, 0.01, '=')) + ',' +
                      '"GstRate": ' + ReturnStr(ROUND(GSTPercen, 0.01, '=')) + ',' +
                      '"SgstAmt": ' + ReturnStr(ROUND(SGSTPer, 0.01, '=')) + ',' +
                      '"CgstAmt": ' + ReturnStr(ROUND(CGSTPer, 0.01, '=')) + ',' +
                      '"IgstAmt": ' + ReturnStr(ROUND(IGSTPer, 0.01, '=')) + ',' +
                      '"CesRate": 0,' +
                      '"CessAmt": 0,' +
                      '"CesNonAdvalAmt": 0,' +
                      '"StateCesRate": 0,' +
                      '"StateCesAmt": 0,' +
                      '"TotItemVal": ' + ReturnStr(ROUND(abs(abs(DetGSTLedEnt."GST Base Amount") + SGSTPer + CGSTPer + IGSTPer + TCAmt))) + ',' +
                      '"OrderLineRef": null,' +
                      '"OriginCountry": null,' +
                      '"ProdSerialNo": null,' +
                      '"TpApiAttribDtls": null' +
                    '}';
                END;

                Req.ADDTEXT(ItemDetails, TtlLength);
                TempLength := STRLEN(ItemDetails);
                TtlLength += TempLength + 1;
            UNTIL SalesInvoiceLine.NEXT = 0;

        ItemDetails := ']' + '}';
        Req.ADDTEXT(ItemDetails, TtlLength);
        TempLength := STRLEN(ItemDetails);
        TtlLength += TempLength + 1;

        //MESSAGE(IRNBody); //Display IRN

        GSTRegistrationNos.GET(Location."GST Registration No.");

        MESSAGE('%1', Req); //Display JSON Req


        /* EinvoiceHttpContent.WriteFrom(Format(Req));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('client_id', EInvoiceSetUp."Client ID");
        EinvoiceHttpHeader.Add('client_secret', EInvoiceSetUp."Client Secret");
        EinvoiceHttpHeader.Add('IPAddress', EInvoiceSetUp."IP Address");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('user_name', GSTRegistrationNos."User Name");
        EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetUp."E-Invoice URl");
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then;
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));

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
                    JOutputObject.Get('Irn', JOutputToken);
                    IRNNo := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('SignedQRCode', JOutputToken);
                    QRText := JOutputToken.AsValue().AsText();
                    JOutputObject.Get('AckNo', JOutputToken);
                    AckNo := JOutputToken.AsValue().AsCode();
                end;
        end;

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
                Message('E-Invoice Generated Successfully!!');
            end;
        end else
            Message('E-Invoice Genreration Failed'); */
    end;




}