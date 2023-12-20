codeunit 50301 "E Way Bill Generation"
{
    Permissions = TableData 112 = rm,
                   TableData 114 = rm,
                   TableData 5740 = rm;

    var
        PostUrl: Text;
        HttpWebRequestMgt: Codeunit 1297;
        body: Text;
        TempBlob: Codeunit "Temp Blob";
        Instr: InStream;
        ApiResult: Text;
        ItemDetails: Text;
        Req: BigText;
        SIHdr: Record 112;
        TempLength: Integer;
        TtlLength: Integer;
        Outstr: OutStream;
        TempBlob1: Codeunit "Temp Blob";
        TransporterGstinVar: Text[50];
        GeneratorGstinVar: Text[50];
        TransporterDateVar: Text[50];
        StatusVar: Text[10];
        EntryNoVar: Integer;
        TextTemp1: Text;
        LocationRec: Record 14;
        TransportMethod: Record 259;
        VehicleNoVar: Code[20];
        VehicleTypeVar: Text[50];
        TransDocNoVar: Text[50];
        TransDocDateVar: Text[20];
        isSuccess: Text;
        SIHExtRec: Record 112;
        APIError: Label 'Error When Contacting API';

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
                    //Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));
            if JResultToken.IsObject then begin
                JResultToken.WriteTo(OutputMessage);
                JOutputObject.ReadFrom(OutputMessage);
            end;
        end;
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
        //Message(JsonTxt);
    end;

    internal procedure GenerateEWayBillFromIRN(var SalesInvoiceHeader: Record 112)
    var
        PostedSalesHdrExt: Record 112;
        TempV: Text;
        TransMethod: Record 259;
        TransMode: Text[20];
        Distance: Decimal;
        txtResponse: Text;
        StringToRead: Text;
        MessageID: Integer;
        Location: Record 14;
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        LocationState: Record State;
        EwayBillN: Text[50];
        EWayBillD: DateTime;
        ShipToCity: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        ShipToState: Code[5];
        ShipToPinCode: Code[6];
        ShipState: Record State;
        BuyerState: Record State;
        TransPMode: Text[10];
        TransPID: Text;
        TransPDesc: Text[55];
        TransDocNo: Text;
        TransDocD: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        GSTRegistrationNos: Record "GST Registration Nos.";
        ShippingAgent: Record 291;
        TpApiDisp: Text;
        ShippingDetails: Text;
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EwaybillDateText: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        RecSalesInvoiceHeader: Record "Sales Invoice Header";
    begin
        EInvoiceSetUp.get;
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        RecSalesInvoiceHeader.RESET;
        RecSalesInvoiceHeader.SETRANGE("No.", SalesInvoiceHeader."No.");
        IF RecSalesInvoiceHeader.FINDFIRST THEN
            IF RecSalesInvoiceHeader."E-Way Bill No." <> '' THEN
                ERROR('EWayBill No. is already generated');

        Clear(TempBlob1);
        Clear(TempBlob);

        PostedSalesHdrExt.RESET;
        PostedSalesHdrExt.SETRANGE("No.", SalesInvoiceHeader."No.");
        IF PostedSalesHdrExt.FINDFIRST THEN;
        CLEAR(TransMethod);

        //IF TransMethod.GET(SalesInvoiceHeader."Transport Method") THEN;
        //IF SalesInvoiceHeader."Transport Method"='' THEN
        //   TransPMode:='null'
        // ELSE
        //TransPMode:=FORMAT(TransMethod."Trans Mode");

        TransPMode := '1';
        IF SalesInvoiceHeader."Distance (Km)" <> 0 THEN
            Distance := SalesInvoiceHeader."Distance (Km)"
        ELSE
            Distance := 0;
        IF SalesInvoiceHeader."Vehicle No." <> '' THEN
            VehicleNo := SalesInvoiceHeader."Vehicle No."
        ELSE
            VehicleNo := 'null';

        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::ODC THEN
            VehicleType := 'O';
        IF SalesInvoiceHeader."Vehicle Type" = SalesInvoiceHeader."Vehicle Type"::Regular THEN
            VehicleType := 'R';

        BuyerState.RESET;
        IF BuyerState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN;
        ShipState.RESET;
        IF ShipState.GET(SalesInvoiceHeader."GST Ship-to State Code") THEN;

        IF (SalesInvoiceHeader."Ship-to Code" = '') THEN BEGIN
            ShipToState := BuyerState."State Code for E-Invoicing";
            ShipToPinCode := SalesInvoiceHeader."Ship-to Post Code"
        END ELSE BEGIN
            ShipToState := ShipState."State Code for E-Invoicing";
            ShipToPinCode := SalesInvoiceHeader."Ship-to Post Code";
        END;

        Location.RESET;
        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        IF GSTRegistrationNos.GET(Location."GST Registration No.") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;
        LocationName := Location.Name;
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';
        // IF NOT(PostedSalesHdrExt."Transporter ID"='') THEN
        //    TransPID:=PostedSalesHdrExt."Transporter ID"
        // ELSE
        IF ShippingAgent.GET(PostedSalesHdrExt."Shipping Agent Code") THEN BEGIN
            TransPID := ShippingAgent."GST Registration No.";
            TransPDesc := ShippingAgent.Name;
        END;

        IF ShippingAgent.GET(SalesInvoiceHeader."Shipping Agent Code") THEN BEGIN
            TransPID := '"TransId":"' + TransPID + '",';
            TransPDesc := '"TransName":"' + TransPDesc + '",';
        END ELSE BEGIN
            TransPID := '"TransId":' + 'null' + ',';
            TransPDesc := '"TransName":' + 'null' + ',';
        END;

        // IF NOT(PostedSalesHdrExt."Transporter Name" = '') THEN
        //   TransPDesc:=PostedSalesHdrExt."Transporter Name"
        // ELSE
        //  TransPDesc:='null';

        IF NOT (SalesInvoiceHeader."LR/RR No." = '') THEN
            TransDocNo := SalesInvoiceHeader."LR/RR No."
        ELSE
            TransDocNo := 'null';
        IF NOT (SalesInvoiceHeader."LR/RR Date" = 0D) THEN
            TransDocD := FORMAT(SalesInvoiceHeader."LR/RR Date", 0, '<Day,2>/<Month,2>/<Year4>')
        //TransDocD := FORMAT(SalesInvoiceHeader."LR/RR Date",0,9)
        ELSE
            TransDocD := 'null';

        TpApiDisp := 'null';

        ShipToAdd := SalesInvoiceHeader."Ship-to Address";
        ShipToAdd2 := SalesInvoiceHeader."Ship-to Address 2";
        ShipToCity := SalesInvoiceHeader."Ship-to City";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        IF SalesInvoiceHeader."Ship-to Code" <> '' THEN
            ShippingDetails := '{"Addr1":"' + ShipToAdd + '",' +
                '"Addr2":"' + ShipToAdd2 + '",' +
                '"Pin":"' + ShipToPinCode + '",' +
                '"Stcd":"' + ShipToState + '",' +
                '"Loc":"' + ShipToCity + '"},'
        ELSE
            ShippingDetails := 'null,';


        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';
        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice';//For UAT--Read

        body := '{' + '"ACTION": "EWAYBILL",' +
          '"IRN":"' + PostedSalesHdrExt."IRN No." + '",' +
          '"Distance":"' + ReturnStr(ROUND(Distance, 0.01, '=')) + '",' +
          '"TransMode":"' + TransPMode + '",' +
          //'"TransId":"'+TransPID+'",'+
          TransPID +
          TransPDesc +
          //  '"TransName":"'+TransPDesc+'",'+
          //'"TransId":'+'null'+','+
          // '"TransName":"'+TransPDesc+'",'+
          '"TransDocDt":' + TransDocD + ',' +
          '"TransDocNo":' + TransDocNo + ',' +
          '"VehNo":"' + VehicleNo + '",' +
          '"VehType":"' + VehicleType + '",' +
           //  '"ExpShipDtls":'+'{'+
           //    '"Addr1":"'+ShipToAdd+'",'+
           //    '"Addr2":"'+ShipToAdd2+'",'+
           //    '"Pin":"'+ShipToPinCode+'",'+
           //    '"Stcd":"'+ShipToState+'",'+
           //    '"Loc":"'+ShipToCity+'",'
           //  +'},'+
           '"ExpShipDtls":' + ShippingDetails +
          //  '"DispDtls": {'+
          //    '"Nm": "'+DelString(LocationName2)+'",'+
          //    '"Addr1": "'+DelString(LocationAdd)+'",'+
          //    '"Addr2": "'+DelString(LocationAdd2)+'",'+
          //    '"Loc": "'+Location.City+'",'+
          //    '"Pin":"'+Location."Post Code"+'",'+
          //    '"Stcd":"'+LocationState."State Code for E-Invoicing"+'"'+
          //  '}'
          '"DispDtls":' + TpApiDisp
        + '}';

        MESSAGE('%1', body); //Display Body

        EinvoiceHttpContent.WriteFrom(Format(body));
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
                    if JOutputObject.Get('EwbDt', JOutputToken) then
                        EwaybillDateText := JOutputToken.AsValue().AsText();
                    Evaluate(YearCode, CopyStr(EwaybillDateText, 1, 4));
                    Evaluate(MonthCode, CopyStr(EwaybillDateText, 6, 2));
                    Evaluate(DayCode, CopyStr(EwaybillDateText, 9, 2));
                    Evaluate(EWayBillDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(EwaybillDateText, 12, 8));
                    if JOutputObject.Get('EwbNo', JOutputToken) then
                        EwayBillN := JOutputToken.AsValue().AsText();
                    SalesInvoiceHeader."E-Way Bill No." := EwayBillN;
                    SalesInvoiceHeader."E-Way Bill Date" := (EWayBillDate);
                    SalesInvoiceHeader.Modify();
                    Message('E-Way Bill Generated Successfully!!');
                end;
        end else
            MESSAGE('E-Way Bill Generation Failed!!');
    end;


    procedure GenerateEWayBillFromIRNSalesCreditMemo(var SalesCrMemoHeader: Record 114)
    var
        PostedSalesHdrExt: Record 114;
        TempV: Text;
        TransMethod: Record 259;
        TransMode: Text[20];
        Distance: Decimal;
        txtResponse: Text;
        StringToRead: Text;
        MessageID: Integer;
        Location: Record 14;
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        LocationState: Record State;
        EwayBillN: Text[50];
        EWayBillD: DateTime;
        ShipToCity: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        ShipToState: Code[5];
        ShipToPinCode: Code[6];
        ShipState: Record State;
        BuyerState: Record State;
        TransPMode: Text[10];
        TransPID: Text[15];
        TransPDesc: Text[30];
        TransDocNo: Text;
        TransDocD: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        GSTRegistrationNos: Record "GST Registration Nos.";
        ShippingAgent: Record 291;
        ShippingDetails: Text;
        TpApiDisp: Text;
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EwaybillDateText: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        JSalesCrHdrObJ: JsonObject;
        JShippingDetails: JsonObject;
        JNullValue: JsonValue;
        JsonMsg: Text;
        EDateTime: DateTime;
        RecSalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        JNullValue.SetValueToNull();
        EInvoiceSetUp.Get();
        CLEAR(HttpWebRequestMgt);
        CLEAR(body);

        RecSalesCrMemoHeader.RESET;
        RecSalesCrMemoHeader.SETRANGE("No.", SalesCrMemoHeader."No.");
        IF RecSalesCrMemoHeader.FINDFIRST THEN
            IF RecSalesCrMemoHeader."E-Way Bill No." <> '' THEN
                ERROR('EWayBill No. is already generated');

        Clear(TempBlob);
        Clear(TempBlob1);

        PostedSalesHdrExt.RESET;
        PostedSalesHdrExt.SETRANGE("No.", SalesCrMemoHeader."No.");
        IF PostedSalesHdrExt.FINDFIRST THEN;
        CLEAR(TransMethod);
        IF TransMethod.GET(SalesCrMemoHeader."Transport Method") THEN;
        // IF SalesCrMemoHeader."Transport Method"='' THEN
        //   TransPMode:='null'
        // ELSE
        // TransPMode:=FORMAT(TransMethod."Trans Mode");
        TransPMode := '1';
        IF SalesCrMemoHeader."Distance (Km)" <> 0 THEN
            Distance := (SalesCrMemoHeader."Distance (Km)")
        ELSE
            Distance := 0;

        IF SalesCrMemoHeader."Vehicle No." <> '' THEN
            VehicleNo := SalesCrMemoHeader."Vehicle No."
        ELSE
            VehicleNo := 'null';

        //IF SalesCrMemoHeader."Vehicle-Type01" = SalesCrMemoHeader."Vehicle-Type01"::" " THEN
        //    VehicleType := 'null';
        IF SalesCrMemoHeader."Vehicle Type" = SalesCrMemoHeader."Vehicle Type"::ODC THEN
            VehicleType := 'O';
        IF SalesCrMemoHeader."Vehicle Type" = SalesCrMemoHeader."Vehicle Type"::Regular THEN
            VehicleType := 'R';
        BuyerState.RESET;
        IF BuyerState.GET(SalesCrMemoHeader."GST Bill-to State Code") THEN;
        ShipState.RESET;
        IF ShipState.GET(SalesCrMemoHeader."GST Ship-to State Code") THEN;

        IF (SalesCrMemoHeader."Ship-to Code" = '') THEN BEGIN
            ShipToState := BuyerState."State Code for E-Invoicing";
            ShipToPinCode := SalesCrMemoHeader."Ship-to Post Code"
        END ELSE BEGIN
            ShipToState := ShipState."State Code for E-Invoicing";
            ShipToPinCode := SalesCrMemoHeader."Ship-to Post Code";
        END;

        Location.RESET;
        IF Location.GET(SalesCrMemoHeader."Location Code") THEN;
        IF GSTRegistrationNos.GET(Location."GST Registration No.") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;
        LocationName := Location.Name;
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';
        //IF NOT(PostedSalesHdrExt."Transporter ID"='') THEN
        //    TransPID:=PostedSalesHdrExt."Transporter ID"
        // ELSE
        // TransPID:='null';
        // IF NOT(PostedSalesHdrExt."Transporter Name" = '') THEN
        //   TransPDesc:=PostedSalesHdrExt."Transporter Name"
        // ELSE
        // TransPDesc:='null';
        //IF NOT(SalesCrMemoHeader."LR/RR No." = '') THEN
        //   TransDocNo:=SalesCrMemoHeader."LR/RR No."
        // ELSE
        //  TransDocNo:='null';
        TransDocNo := 'null';
        //IF NOT(SalesCrMemoHeader."LR/RR Date" = 0D) THEN
        //   TransDocD:=FORMAT(SalesCrMemoHeader."LR/RR Date",0,'<Day,2>/<Month,2>/<Year4>')
        // ELSE
        // TransDocD:='null';
        TransDocD := Format(SalesCrMemoHeader."Posting Date", 0, '<Day,2>/<Month,2>/<Year4>');
        ShipToAdd := SalesCrMemoHeader."Ship-to Address";
        ShipToAdd2 := SalesCrMemoHeader."Ship-to Address 2";
        ShipToCity := SalesCrMemoHeader."Ship-to City";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        TpApiDisp := 'null';

        IF ShippingAgent.GET(SalesCrMemoHeader."Shipping Agent Code") THEN BEGIN
            TransPID := ShippingAgent."GST Registration No.";
            TransPDesc := ShippingAgent.Name;
        END;

        IF ShippingAgent.GET(SalesCrMemoHeader."Shipping Agent Code") THEN BEGIN
            TransPID := '"TransId":"' + TransPID + '",';
            TransPDesc := '"TransName":"' + TransPDesc + '",';
        END ELSE BEGIN
            TransPID := '"TransId":' + 'null' + ',';
            TransPDesc := '"TransName":' + 'null' + ',';
        END;

        IF SalesCrMemoHeader."Ship-to Code" <> '' THEN
            ShippingDetails := '{"Addr1":"' + ShipToAdd + '",' +
                '"Addr2":"' + ShipToAdd2 + '",' +
                '"Pin":"' + ShipToPinCode + '",' +
                '"Stcd":"' + ShipToState + '",' +
                '"Loc":"' + ShipToCity + '"},'
        ELSE
            ShippingDetails := 'null,';


        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';
        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice';//For UAT--Read

        body := '{' + '"ACTION": "EWAYBILL",' +
          '"IRN":"' + PostedSalesHdrExt."IRN No." + '",' +
          '"Distance":"' + ReturnStr(ROUND(Distance, 0.01, '=')) + '",' +
          '"TransMode":"' + TransPMode + '",' +
          //'"TransId":"'+TransPID+'",'+
          TransPID +
          TransPDesc +
          //  '"TransName":"'+TransPDesc+'",'+
          //'"TransId":'+'null'+','+
          // '"TransName":'+TransPDesc+','+
          '"TransDocDt":"' + TransDocD + '",' +
          '"TransDocNo":"' + TransDocNo + '",' +
          '"VehNo":"' + VehicleNo + '",' +
          '"VehType":"' + VehicleType + '",' +
           //  '"ExpShipDtls":'+'{'+
           //    '"Addr1":"'+ShipToAdd+'",'+
           //    '"Addr2":"'+ShipToAdd2+'",'+
           //    '"Pin":"'+ShipToPinCode+'",'+
           //    '"Stcd":"'+ShipToState+'",'+
           //    '"Loc":"'+ShipToCity+'",'
           //  +'},'+
           //  '"DispDtls": {'+
           //    '"Nm": "'+DelString(LocationName2)+'",'+
           //    '"Addr1": "'+DelString(LocationAdd)+'",'+
           //    '"Addr2": "'+DelString(LocationAdd2)+'",'+
           //    '"Loc": "'+Location.City+'",'+
           //    '"Pin":"'+Location."Post Code"+'",'+
           //    '"Stcd":"'+LocationState."State Code for E-Invoicing"+'"'+
           //  '}'
           '"ExpShipDtls":' + ShippingDetails +
          '"DispDtls":' + TpApiDisp
        + '}';

        MESSAGE('%1', body);

        EinvoiceHttpContent.WriteFrom(Format(body));
        //EinvoiceHttpContent.WriteFrom(Format(JsonMsg));
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
                    if JOutputObject.Get('EwbDt', JOutputToken) then
                        EDateTime := JOutputToken.AsValue().AsDateTime();
                    Evaluate(YearCode, CopyStr(EwaybillDateText, 1, 4));
                    Evaluate(MonthCode, CopyStr(EwaybillDateText, 6, 2));
                    Evaluate(DayCode, CopyStr(EwaybillDateText, 9, 2));
                    Evaluate(EWayBillDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(EwaybillDateText, 12, 8));
                    if JOutputObject.Get('EwbNo', JOutputToken) then
                        EwayBillN := JOutputToken.AsValue().AsText();
                    SalesCrMemoHeader."E-Way Bill No." := EwayBillN;
                    SalesCrMemoHeader."E-Way Bill Date" := (EWayBillDate);
                    SalesCrMemoHeader.Modify();
                    Message('E-Way Bill Generated Successfully!!');
                end;
        end else
            MESSAGE('E-Way Bill Generation Failed!!');
    end;


    procedure GenerateEWayBillFromIRNTrfrShipment(var TransferShipmentHeader: Record 5744)
    var
        PostedSalesHdrExt: Record 5744;
        TempV: Text;
        TransMethod: Record 259;
        TransMode: Text[20];
        Distance: Decimal;
        txtResponse: Text;
        StringToRead: Text;
        MessageID: Integer;
        Location: Record 14;
        LocationName: Text;
        LocationName2: Text;
        LocationAdd: Text;
        LocationAdd2: Text;
        LocationState: Record State;
        EwayBillN: Text[50];
        EWayBillD: DateTime;
        ShipToCity: Text;
        ShipToAdd: Text;
        ShipToAdd2: Text;
        ShipToState: Code[5];
        ShipToPinCode: Code[6];
        ShipState: Record State;
        BuyerState: Record State;
        TransPMode: Text[10];
        TransPID: Text;
        TransPDesc: Text;
        TransDocNo: Text;
        TransDocD: Text;
        VehicleNo: Text[20];
        VehicleType: Text[4];
        GSTRegistrationNos: Record "GST Registration Nos.";
        LocationTo: Record 14;
        ShippingAgent: Record 291;
        TpApiDisp: Text;
        ShippingDetails: Text;
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EwaybillDateText: Text;
        EInvoiceSetUp: Record "E-Invoice Set Up 1";
        RecTransferShipmentHeader: Record "Transfer Shipment Header";
    begin
        EInvoiceSetUp.Get();
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        RecTransferShipmentHeader.RESET;
        RecTransferShipmentHeader.SETRANGE("No.", TransferShipmentHeader."No.");
        IF RecTransferShipmentHeader.FINDFIRST THEN
            IF RecTransferShipmentHeader."E-Way Bill No." <> '' THEN
                ERROR('EWayBill No. is already generated');

        Clear(TempBlob);
        Clear(TempBlob1);

        // PostedSalesHdrExt.RESET;
        // PostedSalesHdrExt.SETRANGE("No.",SalesInvoiceHeader."No.");
        // IF PostedSalesHdrExt.FINDFIRST THEN;
        CLEAR(TransMethod);
        IF TransMethod.GET(TransferShipmentHeader."Transport Method") THEN;
        // IF TransferShipmentHeader."Transport Method"='' THEN
        //   TransPMode:='null'
        // ELSE
        // TransPMode:=FORMAT(TransMethod."Trans Mode");
        TransPMode := '1';
        IF TransferShipmentHeader."Distance (Km)" <> 0 THEN
            Distance := TransferShipmentHeader."Distance (Km)"
        ELSE
            Distance := 0;
        IF TransferShipmentHeader."Vehicle No." <> '' THEN
            VehicleNo := TransferShipmentHeader."Vehicle No."
        ELSE
            VehicleNo := 'null';
        //IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::" " THEN
        //    VehicleType := 'null';

        IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::ODC THEN
            VehicleType := 'O';
        IF TransferShipmentHeader."Vehicle Type" = TransferShipmentHeader."Vehicle Type"::Regular THEN
            VehicleType := 'R';

        LocationTo.RESET;
        LocationTo.GET(TransferShipmentHeader."Transfer-to Code");
        BuyerState.RESET;
        IF BuyerState.GET(LocationTo."State Code") THEN;

        // ShipState.RESET;
        // IF ShipState.GET(TransferShipmentHeader."GST Ship-to State Code") THEN;

        // IF (TransferShipmentHeader."Ship-to Code"='') THEN
        //  BEGIN
        //  ShipToState:=BuyerState."State Code for E-Invoicing";
        //  ShipToPinCode:=TransferShipmentHeader."Ship-to Post Code"
        // END ELSE BEGIN
        //  ShipToState:=ShipState."State Code for E-Invoicing";
        //  ShipToPinCode:=TransferShipmentHeader."Ship-to Post Code";
        //  END;

        Location.RESET;
        IF Location.GET(TransferShipmentHeader."Transfer-from Code") THEN;
        IF GSTRegistrationNos.GET(Location."GST Registration No.") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;
        LocationName := Location.Name;
        LocationName2 := Location."Name 2";
        LocationAdd := Location.Address;
        LocationAdd2 := Location."Address 2";
        IF LocationAdd2 = '' THEN
            LocationAdd2 := '   ';
        // IF NOT(PostedSalesHdrExt."Transporter ID"='') THEN
        //    TransPID:=PostedSalesHdrExt."Transporter ID"
        // ELSE
        //  TransPID:='null';
        // IF NOT(PostedSalesHdrExt."Transporter Name" = '') THEN
        //   TransPDesc:=PostedSalesHdrExt."Transporter Name"
        // ELSE
        //  TransPDesc:='null';
        IF ShippingAgent.GET(TransferShipmentHeader."Shipping Agent Code") THEN BEGIN
            TransPID := ShippingAgent."GST Registration No.";
            TransPDesc := ShippingAgent.Name;
        END;   //ELSE BEGIN
               //  TransPID:='null';
               //  TransPDesc:='null';
               // END;

        IF ShippingAgent.GET(TransferShipmentHeader."Shipping Agent Code") THEN BEGIN
            TransPID := '"TransId":"' + TransPID + '",';
            TransPDesc := '"TransName":"' + TransPDesc + '",';
        END ELSE BEGIN
            TransPID := '"TransId":' + 'null' + ',';
            TransPDesc := '"TransName":' + 'null' + ',';
        END;

        IF NOT (TransferShipmentHeader."LR/RR No." = '') THEN
            //TransDocNo:=TransferShipmentHeader."LR/RR No."
            //'"TransDocDt":"'+TransDocD+'",'+
            TransDocNo := '"TransDocNo":"' + TransferShipmentHeader."LR/RR No." + '",'
        ELSE
            TransDocNo := '"TransDocNo":' + 'null' + ',';

        IF NOT (TransferShipmentHeader."LR/RR Date" = 0D) THEN
            //TransDocD:=FORMAT(TransferShipmentHeader."LR/RR Date",0,'<Day,2>/<Month,2>/<Year4>')
            //TransDocD := FORMAT(TransferShipmentHeader."LR/RR Date",0,9)
            TransDocD := '"TransDocDt":"' + FORMAT(TransferShipmentHeader."LR/RR Date", 0, 9) + '",'
        ELSE
            TransDocD := '"TransDocDt":' + 'null' + ',';

        TpApiDisp := 'null';
        // ShipToAdd := TransferShipmentHeader."Ship-to Address";
        // ShipToAdd2 := TransferShipmentHeader."Ship-to Address 2";
        // ShipToCity:=TransferShipmentHeader."Ship-to City";
        IF ShipToAdd2 = '' THEN
            ShipToAdd2 := '   ';

        // IF SalesInvoiceHeader."Ship-to Code"<>'' THEN
        // ShippingDetails:='{"Addr1":"'+ShipToAdd+'",'+
        //    '"Addr2":"'+ShipToAdd2+'",'+
        //    '"Pin":"'+ShipToPinCode+'",'+
        //    '"Stcd":"'+ShipToState+'",'+
        //    '"Loc":"'+ShipToCity+'"},'
        //  ELSE
        ShippingDetails := 'null,';


        //PostUrl := 'https://einvoicetpapi.gstrobo.com/V1/EInvoice';
        //PostUrl := 'http://182.76.79.236:35001/EinvoiceTPApi-QA/einvoice';//For UAT--Read

        body := '{' + '"ACTION": "EWAYBILL",' +
          '"IRN":"' + TransferShipmentHeader."IRN No." + '",' +
          '"Distance":"' + ReturnStr(ROUND(Distance, 0.01, '=')) + '",' +
          // '"Distance":"'+Distance+'",'+
          '"TransMode":"' + TransPMode + '",' +
            TransPID +
            TransPDesc +
            //'"TransId":"'+TransPID+'",'+
            //  '"TransName":"'+TransPDesc+'",'+
            //'"TransId":'+'null'+','+
            //'"TransName":'+TransPDesc+','+
            //  '"TransDocDt":"'+TransDocD+'",'+
            //  '"TransDocNo":"'+TransDocNo+'",'+
            TransDocD +
            TransDocNo +
          '"VehNo":"' + VehicleNo + '",' +
          '"VehType":"' + VehicleType + '",' +
          '"ExpShipDtls":' + ShippingDetails +
          //  '"ExpShipDtls":'+'{'+
          //    '"Addr1":"'+ShipToAdd+'",'+
          //    '"Addr2":"'+ShipToAdd2+'",'+
          //    '"Pin":"'+ShipToPinCode+'",'+
          //    '"Stcd":"'+ShipToState+'",'+
          //    '"Loc":"'+ShipToCity+'",'
          //  +'},'+
          //  '"DispDtls": {'+
          //    '"Nm": "'+DelString(LocationName2)+'",'+
          //    '"Addr1": "'+DelString(LocationAdd)+'",'+
          //    '"Addr2": "'+DelString(LocationAdd2)+'",'+
          //    '"Loc": "'+Location.City+'",'+
          //    '"Pin":"'+Location."Post Code"+'",'+
          //    '"Stcd":"'+LocationState."State Code for E-Invoicing"+'"'+
          //  '}'
          '"DispDtls":' + TpApiDisp
        + '}';

        MESSAGE('%1', body);

        EinvoiceHttpContent.WriteFrom(Format(body));
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
                    if JOutputObject.Get('EwbDt', JOutputToken) then
                        EwaybillDateText := JOutputToken.AsValue().AsText();
                    Evaluate(YearCode, CopyStr(EwaybillDateText, 1, 4));
                    Evaluate(MonthCode, CopyStr(EwaybillDateText, 6, 2));
                    Evaluate(DayCode, CopyStr(EwaybillDateText, 9, 2));
                    Evaluate(EWayBillDate, Format(DMY2Date(DayCode, MonthCode, YearCode)) + ' ' + Copystr(EwaybillDateText, 12, 8));
                    if JOutputObject.Get('EwbNo', JOutputToken) then
                        EwayBillN := JOutputToken.AsValue().AsText();
                    TransferShipmentHeader."E-Way Bill No." := EwayBillN;
                    TransferShipmentHeader."E-Way Bill Date" := (EWayBillDate);
                    TransferShipmentHeader.Modify();
                    Message('E-Way Bill Generated Successfully!!');
                end;
        end else
            MESSAGE('E-Way Bill Generated Failed!!');
    end;

    local procedure ReturnStr(Amt: Decimal): Text
    begin
        EXIT(DELCHR(FORMAT(Amt), '=', ','));
    end;

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

    procedure GenerateInvoiceDetails(var SalesInvoiceHeader: Record 112)
    var
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
        CGSTPer: Text;
        SGSTPer: Text;
        IGSTPer: Text;
        TotItemValue: Decimal;
        DetailedGSTLedgerEntry: Record "Detailed GST Ledger Entry";
        SIL: Record 113;
        DetailedGSTEntry: Record "Detailed GST Ledger Entry";
        CGSTAmt: Decimal;
        SGSTAmt: Decimal;
        IGSTAmt: Decimal;
        EWayBody: Text;
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
        TransType: Text[5];
        ExportCategory: Text[5];
        GSTPayment: Text[4];
        TotAmtinForCurr: Decimal;
        Country: Record 9;
        CountryCode: Text[4];
        CurrCode: Text[5];
        ExportDetails: Text;
        MessageID: Integer;
        ExportState: Code[5];
        ShipExpState: Code[5];
        ExportPinCode: Code[6];
        ShipExpPinCode: Code[6];
        ShipGSTNo: Code[20];
        Distance: Text[5];
        ShipMode: Record 10;
        ShipCountry: Record 9;
        ItemDesc: Text;
        ShippingAgent: Record 291;
        LineAmount: Decimal;
        GSTBaseAmt: Decimal;
        GSTBaseAmtLine: Decimal;
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
        EWayBillDate: DateTime;
        YearCode: Integer;
        MonthCode: Integer;
        DayCode: Integer;
        EwaybillDateText: Text;
        EInvoiceSetup: Record "E-Invoice Set Up 1";

    begin
        EInvoiceSetup.Get();
        Clear(GSTBaseAmt);
        Clear(TotAmtinForCurr);
        Clear(LineAmount);

        CLEAR(ItemDetails);
        CLEAR(HttpWebRequestMgt);
        CLEAR(Req);

        Clear(TempBlob);
        Clear(TempBlob1);

        TtlLength := 1;
        CompanyInformation.GET;

        SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        if SalesInvoiceLine.FindSet() then
            repeat
                LineAmount += SalesInvoiceLine."Line Amount";
            until SalesInvoiceLine.next = 0;


        Location.RESET;
        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;
        LocationState.RESET;
        IF LocationState.GET(Location."State Code") THEN;

        RecState.RESET;
        IF RecState.GET(CompanyInformation."State Code") THEN;

        RecCustomer.RESET;
        IF RecCustomer.GET(SalesInvoiceHeader."Sell-to Customer No.") THEN;
        BuyerState.RESET;
        IF BuyerState.GET(SalesInvoiceHeader."GST Bill-to State Code") THEN;
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Unregistered THEN
            BuyerGSTNo := 'URP';
        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Registered THEN
            BuyerGSTNo := SalesInvoiceHeader."Customer GST Reg. No.";

        IF SalesInvoiceHeader."Distance (Km)" <> 0 THEN
            Distance := FORMAT(SalesInvoiceHeader."Distance (Km)")
        ELSE
            Distance := 'null';

        ShipMode.RESET;
        IF ShipMode.GET(SalesInvoiceHeader."Shipment Method Code") THEN;

        ShipCountry.RESET;
        IF ShipCountry.GET(SalesInvoiceHeader."Ship-to Country/Region Code") THEN;

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
            ShipGSTNo := ShiptoAddress."GST Registration No."
        ELSE
            ShipGSTNo := 'URP';
        IF DetailedGSTLedgerEntry."Reverse Charge" THEN
            ReverseCharge := 'RC'
        ELSE
            ReverseCharge := 'RG';

        IF SalesInvoiceHeader."GST Without Payment of Duty" THEN
            GSTPayment := '"Y"'
        ELSE
            GSTPayment := '"N"';

        ShippingAgent.RESET;
        IF ShippingAgent.GET(SalesInvoiceHeader."Shipping Agent Code") THEN;

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN BEGIN
            CurrCode := '"' + SalesInvoiceHeader."Currency Code" + '"';
            //SalesInvoiceHeader.CALCFIELDS("Amount to Customer");
            TotAmtinForCurr := (LineAmount + CGSTAmt + IGSTAmt + SGSTAmt);
            BuyerGSTNo := 'URP';
            ShipGSTNo := 'URP';
            Country.RESET;
            IF Country.GET(SalesInvoiceHeader."Bill-to Country/Region Code") THEN
                CountryCode := '"' + Country."Country Code for E-Invoicing" + '"';
        END
        ELSE BEGIN
            TotAmtinForCurr := 0;
            GSTPayment := 'null';
            CountryCode := 'null';
            CurrCode := 'null';
        END;

        IF SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export THEN
            ExportDetails := '{"ExpCat": ' + ExportCategory + ',' +
            '"WthPay": ' + GSTPayment + ',' +
            '"TotalInvoiceInvForCur": ' + ReturnStr(TotAmtinForCurr) + ',' +
            '"ForeignCurrency": ' + CurrCode + ',' +
            '"CountryCode": ' + CountryCode + '},'
        ELSE
            ExportDetails := 'null,';

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Bill-to State Code" = '') THEN BEGIN
            ExportState := '99';
            ExportPinCode := '999999'
        END ELSE BEGIN
            ExportState := BuyerState."State Code for E-Invoicing";
            ExportPinCode := SalesInvoiceHeader."Bill-to Post Code";
        END;

        IF (SalesInvoiceHeader."GST Customer Type" = SalesInvoiceHeader."GST Customer Type"::Export) AND (SalesInvoiceHeader."GST Ship-to State Code" = '') THEN BEGIN
            ShipExpState := '99';
            ShipExpPinCode := '999999'
        END ELSE BEGIN
            ShipExpState := ShipState."State Code for E-Invoicing";
            ShipExpPinCode := ShiptoAddress."Post Code";
        END;

        //Calculate Transaction Type
        IF (CompanyInformation."Post Code" = Location."Post Code") AND (RecCustomer."Post Code" = ShiptoAddress."Post Code") THEN
            TransType := 'REG';

        IF (CompanyInformation."Post Code" <> Location."Post Code") AND (RecCustomer."Post Code" = ShiptoAddress."Post Code") THEN
            TransType := 'DIS';

        IF (CompanyInformation."Post Code" = Location."Post Code") AND (RecCustomer."Post Code" <> ShiptoAddress."Post Code") THEN
            TransType := 'SHP';

        IF (CompanyInformation."Post Code" <> Location."Post Code") AND (RecCustomer."Post Code" <> ShiptoAddress."Post Code") THEN
            TransType := 'CMB';
        //Calculate Transaction Type

        IF CompanyInformation."Phone No." <> '' THEN BEGIN
            IF STRLEN(CompanyInformation."Phone No.") = 10 THEN
                CompPhoneNo := CompanyInformation."Phone No."
            ELSE
                CompPhoneNo := 'null';
        END
        ELSE
            CompPhoneNo := 'null';

        IF Location."Phone No." <> '' THEN BEGIN
            IF STRLEN(Location."Phone No.") = 10 THEN
                LocPhone := Location."Phone No."
            ELSE
                LocPhone := 'null';
        END
        ELSE
            LocPhone := 'null';

        IF SalesInvoiceHeader."Bill-to Contact No." <> '' THEN BEGIN
            IF STRLEN(SalesInvoiceHeader."Bill-to Contact No.") = 10 THEN
                CustPhone := SalesInvoiceHeader."Bill-to Contact No."
            ELSE
                CustPhone := 'null';
        END
        ELSE
            CustPhone := 'null';

        IF ShiptoAddress."Phone No." <> '' THEN BEGIN
            IF STRLEN(ShiptoAddress."Phone No.") = 10 THEN
                ShipPhone := ShiptoAddress."Phone No."
            ELSE
                ShipPhone := 'null';
        END
        ELSE
            ShipPhone := 'null';

        IF CompanyInformation."E-Mail" <> '' THEN
            CompEmail := '"' + CompanyInformation."E-Mail" + '"'
        ELSE
            CompEmail := 'null';

        IF Location."E-Mail" <> '' THEN
            LocEmail := '"' + Location."E-Mail" + '"'
        ELSE
            LocEmail := 'null';

        IF RecCustomer."E-Mail" <> '' THEN
            CustEmail := '"' + RecCustomer."E-Mail" + '"'
        ELSE
            CustEmail := 'null';

        IF ShiptoAddress."E-Mail" <> '' THEN
            ShipEmail := '"' + ShiptoAddress."E-Mail" + '"'
        ELSE
            ShipEmail := 'null';


        SIL.RESET;
        SIL.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SIL.SETFILTER("No.", '<>%1', EInvoiceSetup."GL Account Round 1");
        //SIL.CALCSUMS("Tax Base Amount");
        SIL.CALCSUMS("Line Discount Amount");
        //SIL.CALCSUMS("Charges To Customer");//Changes
        //SIL.CALCSUMS("Amount To Customer");

        DetailedGSTEntry.RESET;
        DetailedGSTEntry.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        DetailedGSTEntry.SETRANGE("GST Component Code", 'CGST');
        DetailedGSTEntry.CALCSUMS("GST Amount", "GST Base Amount");
        CGSTAmt := ABS(DetailedGSTEntry."GST Amount");
        GSTBaseAmt := ABS(DetailedGSTLedgerEntry."GST Base Amount");


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
        GSTBaseAmt := ABS(DetailedGSTLedgerEntry."GST Base Amount");

        //PostUrl := 'https://ewbtpapi.gstrobo.com/V1/EwayBill/';

        EWayBody := '{' +
          '"action": "INVOICE",' +
          '"data": [' +
            '{' +
        //      '"GENERATOR_GSTIN": "05AAACE3307P1ZP",'+
              '"GENERATOR_GSTIN": "' + Location."GST Registration No." + '",' +
              '"TRANSACTION_TYPE": "OutWard",' +
              '"TRANSACTION_SUB_TYPE": "Supply",' +
              '"SUPPLY_TYPE": "Regular",' +
              '"TRANS_TYPE_DESC": "",' +
              '"DOC_TYPE": "Tax Invoice",' +
              '"DOC_NO": "' + SalesInvoiceHeader."No." + '",' +
              '"DOC_DATE": "' + FORMAT(SalesInvoiceHeader."Posting Date", 0, 9) + '",' +
        //      '"CONSIGNOR_GSTIN_NO": "05AAACE3307P1ZP",'+
              '"CONSIGNOR_GSTIN_NO": "' + SalesInvoiceHeader."Location GST Reg. No." + '",' +
              '"CONSIGNEE_GSTIN_NO": "' + ShipGSTNo + '",' +
        //      '"CONSIGNEE_GSTIN_NO": "05AAACE1378A1Z9",'+
              '"CONSIGNOR_LEGAL_NAME": "' + DelString(Location.Name) + ' ' + DelString(Location."Name 2") + '",' +
              '"CONSIGNEE_LEGAL_NAME": "' + DelString(SalesInvoiceHeader."Ship-to Name") + ' ' + DelString(SalesInvoiceHeader."Ship-to Name 2") + '",' +
              '"SHIP_ADDRESS_LINE1": "' + DelString(SalesInvoiceHeader."Ship-to Address") + '",' +
              '"SHIP_ADDRESS_LINE2": "' + DelString(SalesInvoiceHeader."Ship-to Address 2") + '",' +
              '"SHIP_STATE": "' + ShipState.Description + '",' +
        //      '"SHIP_STATE": "UTTARAKHAND",'+
              '"SHIP_CITY_NAME": "' + SalesInvoiceHeader."Ship-to City" + '",' +
              '"SHIP_PIN_CODE": "' + SalesInvoiceHeader."Ship-to Post Code" + '",' +
        //      '"SHIP_PIN_CODE": "262542",'+
              '"SHIP_COUNTRY": "' + DelString(ShipCountry.Name) + '",' +
              '"ORIGIN_ADDRESS_LINE1": "' + DelString(Location.Address) + '",' +
              '"ORIGIN_ADDRESS_LINE2": "' + DelString(Location."Address 2") + '",' +
              '"ORIGIN_STATE": "' + LocationState.Description + '",' +
              '"ORIGIN_CITY_NAME": "' + Location.City + '",' +
              '"ORIGIN_PIN_CODE": "' + Location."Post Code" + '",' +
              '"TRANSPORT_MODE": "Road",' +
        //      '"TRANSPORT_MODE": "'+ShipMode."Code for E Way Bill"+'",'+
              '"VEHICLE_TYPE": "' + FORMAT(SalesInvoiceHeader."Vehicle Type") + '",' +
        //      '"VEHICLE_TYPE": "Normal",'+
              '"APPROXIMATE_DISTANCE": ' + Distance + ',' +
        //      '"TRANSPORTER_ID_GSTIN": "05AAACE2097G1ZV",'+
              '"TRANSPORTER_ID_GSTIN": "' + ShippingAgent."GST Registration No." + '",' +
              '"TRANSPORTER_NAME": "",' +
              //'"TRANSPORTER_NAME": "'+ShippingAgent.Name+'",'+
              '"TRANS_DOC_NO": "",' +
              '"TRANS_DOC_DATE": "",' +
              '"TRANS_DOC_NO": "' + SalesInvoiceHeader."LR/RR No." + '",' +
              '"TRANS_DOC_DATE": "' + FORMAT(SalesInvoiceHeader."LR/RR Date", 0, 9) + '",' +   //9509
              '"VEHICLE_NO": "' + SalesInvoiceHeader."Vehicle No." + '",' +
        //      '"VEHICLE_NO": "DL35AB4758",'+
              '"CGST_AMOUNT": ' + ReturnStr(CGSTAmt) + ',' +
              '"SGST_AMOUNT": ' + ReturnStr(SGSTAmt) + ',' +
              '"IGST_AMOUNT": ' + ReturnStr(IGSTAmt) + ',' +
              '"CESS_AMOUNT": 0,' +
              '"TOTAL_TAXABLE_VALUE": ' + ReturnStr(GSTBaseAmt) + ',' +
              //'"TOTAL_TAXABLE_VALUE": ' + ReturnStr(SIL."Tax Base Amount") + ',' +
              '"CESS_NONADVOL_AMOUNT": null,' +
              '"BUSINESS_LINE_CODE": null,' +
               //'"TOTAL_INVOICE_VALUE":' + ReturnStr(SIL."Amount To Customer") + ',' +
               '"TOTAL_INVOICE_VALUE":' + ReturnStr(TotAmtinForCurr) + ',' +
              //'"OTHER_VALUE":' + ReturnStr(SIL."Charges To Customer") + ',' +//Changes
              '"OTHER_VALUE":' + ReturnStr(0) + ',' +
              '"Items": [';

        Req.ADDTEXT(EWayBody, TtlLength);
        TempLength := STRLEN(EWayBody);
        TtlLength += TempLength + 1;

        CGSTPer := 'null';
        SGSTPer := 'null';
        IGSTPer := 'null';

        SalesInvoiceLine.RESET;
        SalesInvoiceLine.SETRANGE("Document No.", SalesInvoiceHeader."No.");
        SalesInvoiceLine.SETFILTER("No.", '<>%1', EInvoiceSetup."GL Account Round 1");
        SalesInvoiceLine.SETFILTER(Quantity, '<>%1', 0);
        IF SalesInvoiceLine.FINDSET THEN
            REPEAT
                DGLEntry.RESET;
                DGLEntry.SETRANGE("Document No.", SalesInvoiceLine."Document No.");
                DGLEntry.SETRANGE("Document Line No.", SalesInvoiceLine."Line No.");
                DGLEntry.SETRANGE("No.", SalesInvoiceLine."No.");
                IF DGLEntry.FINDSET THEN
                    REPEAT
                        IF DGLEntry."GST Component Code" = 'CGST' THEN begin
                            CGSTPer := FORMAT(DGLEntry."GST %");
                            GSTBaseAmtLine := DGLEntry."GST Base Amount";
                        end;
                        IF DGLEntry."GST Component Code" = 'SGST' THEN
                            SGSTPer := FORMAT(DGLEntry."GST %");
                        IF DGLEntry."GST Component Code" = 'IGST' THEN begin
                            IGSTPer := FORMAT(DGLEntry."GST %");
                            GSTBaseAmtLine := DGLEntry."GST Base Amount";
                        end;
                    UNTIL DGLEntry.NEXT = 0;
                //TotItemValue:=(SalesInvoiceLine."Tax Base Amount")*(1+(CGSTPer+SGSTPer+IGSTPer));

                UnitofMeasure.RESET;
                UnitofMeasure.SETRANGE(Code, SalesInvoiceLine."Unit of Measure Code");
                IF UnitofMeasure.FINDFIRST THEN
                    UOM := UnitofMeasure."UOM For E Invoicing";

                IF STRLEN(SalesInvoiceLine.Description) < 31 THEN
                    ItemDesc := SalesInvoiceLine.Description
                ELSE
                    ItemDesc := COPYSTR(DELCHR(SalesInvoiceLine.Description, '=', '"'), 1, 30);

                IF ItemDetails = '' THEN BEGIN
                    ItemDetails := '{' +
                    '"IGST_RATE": ' + IGSTPer + ',' +
                    '"CGST_RATE": ' + CGSTPer + ',' +
                    '"SGST_RATE": ' + SGSTPer + ',' +
                    '"CESS_RATE": 0,' +
                    '"CESS_NONADVOL": 0,' +
                    '"ITEM_NAME": "' + ItemDesc + '",' +
                    '"HSN_CODE": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                    '"UOM": "' + UOM + '",' +
                    '"QUANTITY": ' + ReturnStr(SalesInvoiceLine.Quantity) + ',' +
                    '"TAXABLE_VALUE": ' + ReturnStr(GSTBaseAmtLine) + '' +
                  '}';

                END ELSE BEGIN
                    ItemDetails := ',{' +
                          '"IGST_RATE": ' + IGSTPer + ',' +
                          '"CGST_RATE": ' + CGSTPer + ',' +
                          '"SGST_RATE": ' + SGSTPer + ',' +
                          '"CESS_RATE": 0,' +
                          '"CESS_NONADVOL": 0,' +
                          '"ITEM_NAME": "' + ItemDesc + '",' +
                          '"HSN_CODE": "' + SalesInvoiceLine."HSN/SAC Code" + '",' +
                          '"UOM": "' + UOM + '",' +
                          '"QUANTITY": ' + ReturnStr(SalesInvoiceLine.Quantity) + ',' +
                          '"TAXABLE_VALUE": ' + ReturnStr(GSTBaseAmtLine) + '' +
                        '}';
                END;
                Req.ADDTEXT(ItemDetails, TtlLength);
                TempLength := STRLEN(ItemDetails);
                TtlLength += TempLength + 1;
            UNTIL SalesInvoiceLine.NEXT = 0;

        ItemDetails := ']' + '}' + ']' + '}';
        Req.ADDTEXT(ItemDetails, TtlLength);
        TempLength := STRLEN(ItemDetails);
        TtlLength += TempLength + 1;

        MESSAGE('%1', Req);

        EinvoiceHttpContent.WriteFrom(Format(Req));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.Add('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('Gstin', '05AAACE2097G1ZV');
        //EinvoiceHttpHeader.Add('Gstin', Location."GST Registration No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri('http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/');
        EinvoiceHttpRequest.Method := 'POST';
        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));
                end else
                    if JResultObject.Get('Message', JResultToken) then
                        Message(Format(JResultToken));
            if JResultObject.Get('Data', JResultToken) then
                if JResultToken.IsObject then begin
                    JResultToken.WriteTo(OutputMessage);
                    JOutputObject.ReadFrom(OutputMessage);
                    Message(OutputMessage);
                end;
        end else
            MESSAGE(APIError);
    end;


    procedure CancelEWayBill(var SalesInvoiceHeader: Record 112)
    var
        StringToRead: Text;
        Remarks: Text;
        Location: Record 14;
        APIException: Text;
        APIStatus: Text;
        Body: Text;
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
        EInvoiceSetup: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetup.Get();

        IF SalesInvoiceHeader."E-Way Bill No." = '' THEN
            ERROR('EWay Bill No. can not be blank');

        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;

        SIHExtRec.RESET;
        SIHExtRec.SETRANGE("No.", SalesInvoiceHeader."No.");
        IF SIHExtRec.FINDFIRST THEN;


        Body := '{' +
         '"action": "CANCEL",'
           + '"data": ['
          + '{'
        + '"Generator_Gstin": "' + FORMAT(SalesInvoiceHeader."Location GST Reg. No.") + '",'
           + '"ewbNo": "' + FORMAT(SalesInvoiceHeader."E-Way Bill No.") + '",'
         + '"CancelReason": "' + FORMAT(SIHExtRec."Cancel Reason") + '",'
           + '"cancelRmrk": "' + FORMAT(SIHExtRec."Cancel Remarks") + '",'
          + '}'
           + ']'
         + '}';

        EinvoiceHttpContent.WriteFrom(Format(Body));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();



        // For Productuion
        EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.Add('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('Gstin', SalesInvoiceHeader."Location GST Reg. No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetup."Cancel E-Way URL");
        EinvoiceHttpRequest.Method := 'POST';
        // For Productuion


        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            //Message(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    SalesInvoiceHeader."E-Way Bill No." := '';
                    SalesInvoiceHeader.modify;
                    Message('E-Way Bill Canceled');
                end else
                    Message('Failed');
        end;
    END;

    procedure CancelEWayBillCrMemo(var SalesInvoiceHeader: Record "Sales Cr.Memo Header")
    var
        StringToRead: Text;
        Remarks: Text;
        Location: Record 14;
        APIException: Text;
        APIStatus: Text;
        Body: Text;
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
        EInvoiceSetup: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetup.Get();
        //PostUrl := 'https://ewbtpapi.gstrobo.com/V1/EwayBill/';
        //PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/';

        IF SalesInvoiceHeader."E-Way Bill No." = '' THEN
            ERROR('EWay Bill No. can not be blank');

        IF Location.GET(SalesInvoiceHeader."Location Code") THEN;


        Body := '{' +
         '"action": "CANCEL",'
           + '"data": ['
          + '{'
        + '"Generator_Gstin": "' + FORMAT(SalesInvoiceHeader."Location GST Reg. No.") + '",'
           + '"ewbNo": "' + FORMAT(SalesInvoiceHeader."E-Way Bill No.") + '",'
         + '"CancelReason": "' + FORMAT(SalesInvoiceHeader."Cancel Reason") + '",'
           + '"cancelRmrk": "' + FORMAT(SalesInvoiceHeader."Cancel Remarks") + '",'
          + '}'
           + ']'
         + '}';

        EinvoiceHttpContent.WriteFrom(Format(Body));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        // For Productuion
        EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.Add('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('Gstin', SalesInvoiceHeader."Location GST Reg. No.");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetup."Cancel E-Way URL");
        EinvoiceHttpRequest.Method := 'POST';
        // For Productuion


        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            //Message(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    SalesInvoiceHeader."E-Way Bill No." := '';
                    SalesInvoiceHeader.modify;
                    Message('E-Way Bill Canceled');
                end else
                    Message('Failed');
        end;
    END;


    procedure CancelEWayBillTransfer(var SalesInvoiceHeader: Record "Transfer Shipment Header")
    var
        StringToRead: Text;
        Remarks: Text;
        Location: Record 14;
        APIException: Text;
        APIStatus: Text;
        Body: Text;
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
        EInvoiceSetup: Record "E-Invoice Set Up 1";
    begin
        EInvoiceSetup.Get();
        //PostUrl := 'https://ewbtpapi.gstrobo.com/V1/EwayBill/';
        //PostUrl := 'http://182.76.79.236:35001/EWBTPApi-uat/EwayBill/';

        IF SalesInvoiceHeader."E-Way Bill No." = '' THEN
            ERROR('EWay Bill No. can not be blank');

        IF Location.GET(SalesInvoiceHeader."Transfer-from Code") THEN;


        Body := '{' +
         '"action": "CANCEL",'
           + '"data": ['
          + '{'
        + '"Generator_Gstin": "' + FORMAT(SalesInvoiceHeader."Transfer-from Code") + '",'
           + '"ewbNo": "' + FORMAT(SalesInvoiceHeader."E-Way Bill No.") + '",'
         + '"CancelReason": "' + FORMAT(SalesInvoiceHeader."Cancel Reason") + '",'
           + '"cancelRmrk": "' + FORMAT(SalesInvoiceHeader."Cancel Remarks") + '",'
          + '}'
           + ']'
         + '}';

        EinvoiceHttpContent.WriteFrom(Format(Body));
        EinvoiceHttpContent.GetHeaders(EinvoiceHttpHeader);
        EinvoiceHttpHeader.Clear();
        // For Productuion
        EinvoiceHttpHeader.Add('PRIVATEKEY', EInvoiceSetup."Private Key");
        EinvoiceHttpHeader.Add('PRIVATEVALUE', EInvoiceSetup."Private Value");
        EinvoiceHttpHeader.Add('IP', EInvoiceSetup."Download IP");
        EinvoiceHttpHeader.Add('Content-Type', 'application/json');
        EinvoiceHttpHeader.Add('Gstin', SalesInvoiceHeader."Transfer-from Code");
        EinvoiceHttpRequest.Content := EinvoiceHttpContent;
        EinvoiceHttpRequest.SetRequestUri(EInvoiceSetup."Cancel E-Way URL");
        EinvoiceHttpRequest.Method := 'POST';
        // For Productuion


        if EinvoiceHttpClient.Send(EinvoiceHttpRequest, EinvoiceHttpResponse) then begin
            EinvoiceHttpResponse.Content.ReadAs(ResultMessage);
            JResultObject.ReadFrom(ResultMessage);
            //Message(ResultMessage);

            if JResultObject.Get('MessageId', JResultToken) then
                if JResultToken.AsValue().AsInteger() = 1 then begin
                    SalesInvoiceHeader."E-Way Bill No." := '';
                    SalesInvoiceHeader.modify;
                    Message('E-Way Bill Canceled');
                end else
                    Message('Failed');
        end;
    END;
}