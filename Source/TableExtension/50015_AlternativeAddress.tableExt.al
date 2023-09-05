tableextension 50015 AlternativeAddress extends "Alternative Address"
{
    fields
    {
        field(50005; "EIN_State"; Code[20])
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}