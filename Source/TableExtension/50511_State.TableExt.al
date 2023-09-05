tableextension 50511 State extends State
{
    fields
    {
        field(50100; "State Code for E-Invoicing"; Code[2])
        {
            DataClassification = ToBeClassified;
        }
    }

    var
        myInt: Integer;
}