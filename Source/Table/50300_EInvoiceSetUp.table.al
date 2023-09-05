table 50300 "E-Invoice Set Up 1"
{
    DataClassification = ToBeClassified;

    fields
    {
        field(1; Primary; code[20])
        {
            DataClassification = ToBeClassified;
        }
        field(2; "Client ID"; Text[50])
        {
            DataClassification = ToBeClassified;
        }
        field(5; "Client Secret"; text[50])
        {
            DataClassification = ToBeClassified;
        }
        field(7; "IP Address"; text[20])
        {
            DataClassification = ToBeClassified;
        }
        field(9; "Authentication URL"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(10; "E-Invoice URl"; text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(12; "GL Account Round 1"; Code[20])
        {
            DataClassification = ToBeClassified;
        }
        field(13; "GL Account Round 2"; Code[20])
        {
            DataClassification = ToBeClassified;
        }
        field(14; "Download E-Way Bill URL"; Text[250])
        {
            DataClassification = ToBeClassified;
        }
        field(15; "Private Key"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(16; "Private Value"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(17; "Download IP"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(22; "URL Get IRN"; Text[200])
        {
            DataClassification = ToBeClassified;
        }
        field(18; "Cancel E-Way URL"; Text[250])
        {
            DataClassification = ToBeClassified;
        }
        field(19; "Private IP"; Code[20])
        {
            DataClassification = ToBeClassified;
        }
        field(20; "E-Way Bill URL"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
        field(21; "Dynamics QR URL"; Text[100])
        {
            DataClassification = ToBeClassified;
        }
    }

    keys
    {
        key(Key1; Primary)
        {
            Clustered = true;
        }
    }

    var
        myInt: Integer;

    trigger OnInsert()
    begin

    end;

    trigger OnModify()
    begin

    end;

    trigger OnDelete()
    begin

    end;

    trigger OnRename()
    begin

    end;

}