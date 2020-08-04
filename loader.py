import json

infected = ['64c0a6f2-9900-44d7-ac44-17d8b3e388e0',
            '1a57a4a3-0815-48a2-98be-00375fa5bda8']
with open('contact_list') as json_file:
    contacts = json.load(json_file)

    metWithInfected = {key: [] for key in infected}

    for infect in infected:
        for contact in contacts:
            if(contact['agent_1'] == infect):
                metWithInfected[infect].append(contact['agent_2'])

print(metWithInfected)
