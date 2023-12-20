tableextension 50512 GSTRegistrationNo extends "GST Registration Nos."
{
    fields
    {
        field(50101; "E-Invoice User Name"; Text[30])
        {
            DataClassification = ToBeClassified;
        }
        /* field(50102; "Password"; Text[30])
        {
            DataClassification = ToBeClassified;
        } */
    }

    var
        myInt: Integer;
}